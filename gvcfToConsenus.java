import java.io.File;  // Import the File class
import java.io.FileNotFoundException;  // Import this class to handle errors
import java.util.Scanner; // Import the Scanner class to read text files
import java.util.ArrayList; // Import the ArrayList class
import java.util.List; // Import the ArrayList class

public class gvcfToConsenus{
    public static ArrayList<String> gvcfFileStrings = new ArrayList<String>();
    public static List<List<String>> parsedGVCFFileStrings = new ArrayList<List<String>>();

    // Read gvcf file and store strings into a list
    public static void getGVCFFile (File inputGVCF){
        try {
            Scanner reader = new Scanner(inputGVCF);
            while (reader.hasNextLine()) {
                gvcfFileStrings.add(reader.nextLine());
            }
            reader.close();
        } catch (FileNotFoundException e) {
            System.out.println("An error occurred.");
            e.printStackTrace();
        }
    }

    // Parse strings of gvcf file and store into a list
    public static void parseGVCFFileStrings (){
        ArrayList<String> strArrayTemp;
        for(String strTemp : gvcfFileStrings){
            strArrayTemp = new ArrayList<String>();
            String[] temp = strTemp.split("\t");
            for(String strParseTemp : temp){
                strArrayTemp.add(strParseTemp);
            }
            parsedGVCFFileStrings.add(strArrayTemp);
        }
    }
}