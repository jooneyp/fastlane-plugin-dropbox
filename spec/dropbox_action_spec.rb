require 'dropbox_api'

class String
  def name
    File.basename(self)
  end
end

describe Fastlane::Actions::DropboxAction do
  describe '#run' do
    let(:file_path) { '/path/to/file.txt' }
    let(:dropbox_path) { '/dropbox-folder' }
    let(:destination_path) { "#{dropbox_path}/#{File.basename(file_path)}" }
    let(:file_data) { 'file-data' }

    let(:params) do
      {
        file_path: file_path,
        dropbox_path: dropbox_path,
        app_key: 'dropbox-app-key',
        app_secret: 'dropbox-app-secret',
        keychain: '/path/to/keychain',
        keychain_password: 'very-secret-password'
      }
    end

    shared_context 'with valid parameters' do
      before do
        allow_any_instance_of(DropboxApi::Client).to receive(:upload)
          .with(destination_path, file_data)
          .and_return(destination_path)
        allow(Fastlane::Actions::DropboxAction).to receive(:get_token_from_keychain)
          .with(params[:keychain], params[:keychain_password])
          .and_return('4CC355-T0K3N')
      end
    end

    describe 'small file' do
      let(:file_size) { 16_384 }

      before do
        allow(File).to receive(:size)
          .with(params[:file_path])
          .and_return(file_size)
        allow(File).to receive(:read)
          .with(params[:file_path])
          .and_return(file_data)
      end

      include_context 'with valid parameters' do
        it 'should be uploaded to dropbox' do
          expect(Fastlane::UI).to receive(:success).with("Successfully uploaded archive to Dropbox at '#{destination_path}'")
          Fastlane::Actions::DropboxAction.run(params)
        end
      end
    end

    describe 'huge file' do
      let(:file_size) { 650 * 1024 * 1024 }
      let(:file_parts) { (1..650 / 150 + 1).map { |i| "./part000#{i}" } }

      before do
        allow(File).to receive(:size)
          .and_return(file_size)
        allow(File).to receive(:delete)
          .and_return(nil)
        allow(File).to receive(:read)
          .and_return(file_data)

        allow(Fastlane::Actions::DropboxAction).to receive(:chunker)
          .and_return(file_parts)

        allow_any_instance_of(DropboxApi::Client).to receive(:upload_session_start)
          .and_return('cursor')
        allow_any_instance_of(DropboxApi::Client).to receive(:upload_session_append_v2)
          .and_return('cursor')
        allow_any_instance_of(DropboxApi::Client).to receive(:upload_session_finish)
          .and_return(destination_path)
      end

      include_context 'with valid parameters' do
        it 'should be uploaded to dropbox' do
          expect(Fastlane::UI).to receive(:important).with(/big file/)
          expect(Fastlane::UI).to receive(:success).with("Successfully uploaded archive to Dropbox at '#{destination_path}'")
          expect_any_instance_of(DropboxApi::Client).to receive(:upload_session_start)
            .exactly(1).times
          expect_any_instance_of(DropboxApi::Client).to receive(:upload_session_append_v2)
            .exactly(file_parts.size - 1).times
          expect_any_instance_of(DropboxApi::Client).to receive(:upload_session_finish)
            .exactly(1).times

          Fastlane::Actions::DropboxAction.run(params)

          expect(File).to have_received(:size).exactly(1 + file_parts.size).times
          file_parts.each do |part|
            expect(File).to have_received(:delete).with(part)
          end
        end
      end
    end
  end
end
