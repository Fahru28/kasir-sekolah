class StudentsController < ApplicationController
  def index
    @students = Student.order(:name)
  end

  def template
    package = Axlsx::Package.new
    wb = package.workbook
    wb.add_worksheet(name: "Data_Anak") do |sheet|
      sheet.add_row %w[ID_Anak NIS Nama_Anak Kelas Nama_Wali WA Alamat Status_Aktif]
      sheet.add_row %w[A-011 1011 Contoh\ Siswa 1A Budi 08123456789 Jl.\ Contoh\ 1 Aktif]
      sheet.add_row %w[A-012 1012 Contoh\ Siswi 1B Siti 08123456790 Jl.\ Contoh\ 2 Aktif]
    end
    send_data package.to_stream.read, filename: "Template_Data_Anak.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  def import_form
  end

  def import
    file = params[:file]
    if file.blank?
      redirect_to import_form_students_path, alert: "Pilih file Excel dulu." and return
    end

    ext = File.extname(file.original_filename).downcase
    begin
      rows =
        if ext == ".csv"
          require "csv"
          CSV.read(file.path, headers: true).map { |r| r.to_h }
        else
          xlsx = Roo::Spreadsheet.open(file.path, extension: ext.delete("."))
          # Use first sheet
          xlsx.default_sheet = xlsx.sheets.first
          header = xlsx.row(1).map { |h| h.to_s.strip }
          (2..xlsx.last_row).map do |i|
            row = xlsx.row(i)
            header.each_with_index.to_h { |h, idx| [h, row[idx]] }
          end
        end
    rescue => e
      redirect_to import_form_students_path, alert: "Gagal membaca file: #{e.message}" and return
    end

    created = 0
    updated = 0
    errors = []

    rows.each_with_index do |r, idx|
      # Normalize keys: case-insensitive
      norm = {}
      r.each { |k, v| norm[k.to_s.strip.downcase] = v.to_s.strip }

      code = norm["id_anak"] || norm["id"] || norm["kode"] || norm["code"]
      name = norm["nama_anak"] || norm["nama"] || norm["name"]
      next if code.blank? && name.blank? # skip empty rows

      if code.blank?
        errors << "Baris #{idx + 2}: ID_Anak kosong"
        next
      end
      if name.blank?
        errors << "Baris #{idx + 2}: Nama_Anak kosong (#{code})"
        next
      end

      klass   = norm["kelas"] || norm["class_name"] || ""
      nis     = norm["nis"] || ""
      wali    = norm["nama_wali"] || norm["wali"] || norm["guardian_name"] || ""
      wa      = norm["wa"] || norm["phone"] || norm["telp"] || ""
      alamat  = norm["alamat"] || norm["address"] || ""
      status  = norm["status_aktif"] || norm["status"] || "Aktif"
      active  = !status.to_s.strip.downcase.match?(/nonaktif|tidak|inactive|false|0/)

      student = Student.find_or_initialize_by(code: code)
      is_new = student.new_record?
      student.assign_attributes(
        nis: nis.presence || student.nis,
        name: name,
        class_name: klass.presence || student.class_name,
        guardian_name: wali.presence || student.guardian_name,
        phone: wa.presence || student.phone,
        address: alamat.presence || student.address,
        active: active
      )
      if student.save
        is_new ? created += 1 : updated += 1
      else
        errors << "Baris #{idx + 2} (#{code}): #{student.errors.full_messages.join(', ')}"
      end
    end

    msg = "Import selesai: #{created} baru, #{updated} diperbarui."
    msg += " Ada #{errors.size} error." if errors.any?
    flash[:import_errors] = errors.first(10) if errors.any?
    redirect_to students_path, notice: msg
  end

  def show
    @student = Student.find(params[:id])
    @sales = @student.sales.order(sale_date: :desc)
  end

  def new
    @student = Student.new
  end

  def create
    @student = Student.new(student_params)
    if @student.save
      redirect_to students_path, notice: "Siswa ditambahkan"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @student = Student.find(params[:id])
  end

  def update
    @student = Student.find(params[:id])
    if @student.update(student_params)
      redirect_to students_path, notice: "Siswa diperbarui"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @student = Student.find(params[:id])
    @student.destroy
    redirect_to students_path, notice: "Siswa dihapus"
  end

  private

  def student_params
    params.require(:student).permit(:code, :nis, :name, :class_name, :guardian_name, :phone, :address, :active)
  end
end
