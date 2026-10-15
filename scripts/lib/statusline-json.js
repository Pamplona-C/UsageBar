// Lê e altera só a chave `statusLine` do settings.json do Claude Code (JXA: vem em todo macOS 14+).
// Preserva a ordem das chaves e grava com 2 espaços, o mesmo formato do Claude Code, para que
// instalar e desinstalar devolva o arquivo idêntico.
//
// Uso: osascript -l JavaScript statusline-json.js <comando> <settings.json> [argumento]
//   get          imprime o statusLine atual em JSON, ou `null`
//   get-command  imprime statusLine.command, ou nada
//   point-to     aponta statusLine.command para <argumento>, mantendo os outros campos do statusLine
//   restore      grava <argumento> (JSON) como statusLine; `null` remove a chave
ObjC.import('Foundation');

function readSettings(path) {
  if (!$.NSFileManager.defaultManager.fileExistsAtPath(path)) return {};
  const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  if (text.isNil()) throw new Error('não foi possível ler ' + path);
  return JSON.parse(text.js);
}

function writeSettings(path, settings) {
  const text = $(JSON.stringify(settings, null, 2) + '\n');
  if (!text.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) {
    throw new Error('não foi possível gravar ' + path);
  }
}

function run(argv) {
  const [command, path, argument] = argv;
  const settings = readSettings(path);
  const statusLine = settings.statusLine;

  switch (command) {
    case 'get':
      return statusLine === undefined ? 'null' : JSON.stringify(statusLine);
    case 'get-command':
      return (statusLine && typeof statusLine.command === 'string') ? statusLine.command : '';
    case 'point-to': {
      const base = (statusLine && typeof statusLine === 'object') ? statusLine : {};
      settings.statusLine = Object.assign({}, base, { type: 'command', command: argument });
      writeSettings(path, settings);
      return '';
    }
    case 'restore': {
      const original = JSON.parse(argument);
      if (original === null) {
        delete settings.statusLine;
      } else {
        settings.statusLine = original;
      }
      writeSettings(path, settings);
      return '';
    }
    default:
      throw new Error('comando desconhecido: ' + command);
  }
}
