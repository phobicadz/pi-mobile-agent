// Classic FizzBuzz.
//
// For numbers 1 to n:
//   - print "Fizz" if divisible by 3
//   - print "Buzz" if divisible by 5
//   - print "FizzBuzz" if divisible by both
//   - otherwise print the number itself
//
// Usage:
//   dotnet run -- [n]

int limit = args.Length > 0 && int.TryParse(args[0], out int n) ? n : 100;

for (int i = 1; i <= limit; i++)
{
    if (i % 15 == 0)
        Console.WriteLine("FizzBuzz");
    else if (i % 3 == 0)
        Console.WriteLine("Fizz");
    else if (i % 5 == 0)
        Console.WriteLine("Buzz");
    else
        Console.WriteLine(i);
}
