class TextNormalizer {
  static final Map<String, String> _numberWords = {
    'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
    'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
    'ten': '10', 'eleven': '11', 'twelve': '12', 'thirteen': '13',
    'fourteen': '14', 'fifteen': '15', 'sixteen': '16', 'seventeen': '17',
    'eighteen': '18', 'nineteen': '19', 'twenty': '20', 'thirty': '30',
    'forty': '40', 'fifty': '50', 'sixty': '60',
  };

  static String normalize(String input) {
    // 1. Lowercase
    String text = input.toLowerCase();

    // 2. Custom phrases from your dataset
    text = text.replaceAll('half an hour', '30 minutes');
    text = text.replaceAll('a couple of', '2');
    text = text.replaceAll('an hour', '1 hour');
    text = text.replaceAll("o'clock", ":00");
    text = text.replaceAll("noon", "12:00 pm");
    text = text.replaceAll("midnight", "12:00 am");

    // 3. Remove punctuation (keep colons for time like 10:30)
    text = text.replaceAll(RegExp(r'[^\w\s:]'), '');

    // 4. Convert word numbers to digits
    _numberWords.forEach((word, digit) {
      text = text.replaceAll(RegExp(r'\b' + word + r'\b'), digit);
    });

    return text.trim();
  }
}
