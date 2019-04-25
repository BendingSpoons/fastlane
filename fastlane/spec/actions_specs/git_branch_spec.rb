describe Fastlane::Actions::GitBranchAction do
  describe "CI set ENV values" do
    Fastlane::Actions::SharedValues::GIT_BRANCH_ENV_VARS.each do |env_var|
      it "can control the output of the action with #{env_var}" do
        FastlaneSpec::Env.with_env_values(env_var => "#{env_var}-branch-name") do
          result = Fastlane::FastFile.new.parse("lane :test do
            git_branch
          end").runner.execute(:test)

          expect(result).to eq("#{env_var}-branch-name")
        end
      end
    end
  end

  describe "with no CI set ENV values" do
    it "gets the value from Git directly" do
      skip("Doesn't work in Travis CI (git always returns the true branch) Update April 2021: Still valid?")
      expect(Fastlane::Actions).to receive(:sh)
        .with("git rev-parse --abbrev-ref HEAD", log: false)
        .and_return("branch-name")

      result = Fastlane::FastFile.new.parse("lane :test do
        git_branch
      end").runner.execute(:test)

      expect(result).to eq("branch-name")
    end

    it "returns empty string if git is at HEAD" do
      expect(Fastlane::Actions).to receive(:sh)
        .with("git rev-parse --abbrev-ref HEAD", log: false)
        .and_return("HEAD")

      result = Fastlane::FastFile.new.parse("lane :test do
        git_branch
      end").runner.execute(:test)

      expect(result).to eq("")
    end
  end
end
