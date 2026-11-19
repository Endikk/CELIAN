// Toy Yeoman generator for BENCH-002. Writes the same files as the Copier
// and Cookiecutter templates.
import Generator from 'yeoman-generator';

const STATIC_FILES = ['app.conf', 'pipeline.yml', 'NOTICE.txt'];

export default class extends Generator {
  constructor(args, opts) {
    super(args, opts);
    this.option('projectname', { type: String, default: 'demo' });
  }

  writing() {
    this.fs.copyTpl(
      this.templatePath('PROJECT.txt'),
      this.destinationPath('PROJECT.txt'),
      { projectName: this.options.projectname },
    );
    for (const file of STATIC_FILES) {
      this.fs.copy(this.templatePath(file), this.destinationPath(file));
    }
  }
}
