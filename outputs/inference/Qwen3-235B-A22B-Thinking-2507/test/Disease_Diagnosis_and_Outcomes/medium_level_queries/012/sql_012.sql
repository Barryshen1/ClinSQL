with heart failure, stratified by ICU vs non‑ICU, LOS <8 vs ≥8, and comorbidity burden (0–1/2/≥3), report mortality (%), median LOS, CKD and diabetes prevalence."

We break down the requirements:

1. Population: Women aged 83-93 with heart failure.
   - We need to get patients from `patients` table (for gender and age) and then filter for heart failure (which we'll get from diagnoses_icd).

2. Heart failure: We need to identify heart failure diagnoses. In MIMIC-IV, heart failure is typically coded with ICD codes. 
   - For ICD-10 (version 10), common codes for heart failure are I50.* (e.g., I50.1, I50.2, etc.). However, note that the question does not specify the type of heart failure, so we might consider any heart failure code.
   - We can use the `d_icd_diagnoses` table to get the long_title and look for heart failure. But note: the question says "heart failure", so we should capture all heart failure codes.

   However, note: the `diagnoses_icd` table has `icd_code` and `icd_version`. We need to consider both ICD-9 and ICD-10.

   Common heart failure codes:
     - ICD-9: 428.*
     - ICD-10: I50.*

   We can create a list of codes. But note: the question does not specify the exact codes, so we'll use a standard set.

   According to common practice in MIMIC, we can use:
     - For ICD-9: codes starting with '428'
     - For ICD-10: codes starting with 'I50'

   However, note: the `icd_code` in `diagnoses_icd` is stored without the decimal. So:
     - ICD-9: '428' would be stored as '428' (but note: there are codes like 4280, 4281, etc. so we can use LIKE '428%')
     - ICD-10: 'I50' would be stored as 'I50' (but note: the table stores without the decimal, so I50.1 becomes 'I501') -> so we can use LIKE 'I50%'

   But caution: ICD-10 codes are alphanumeric and the table stores them without the decimal. So:
        I50.1 -> 'I501'
        I50.2 -> 'I502'

   So we can do: 
        (icd_version = 9 AND icd_code LIKE '428%') OR (icd_version = 10 AND icd_code LIKE 'I50%')

   However, note: the `icd_code` in the table is stored as a string. Also, there might be leading zeros in ICD-9? Actually, in MIMIC-IV, ICD-9 codes are stored as strings without leading zeros? But the example in the schema says: `icd_code` for diagnoses_icd is string.

   According to MIMIC-IV documentation, ICD-9 codes are stored without leading zeros and without the decimal. So 428.0 becomes '4280'. Similarly, ICD-10 codes are stored without the decimal.

   So we can use:
        (icd_version = 9 AND icd_code LIKE '428%') 
        OR (icd_version = 10 AND icd_code LIKE 'I50%')

   But note: there are also codes for heart failure in other categories? We'll stick to these.

3. Age: We have `anchor_age` in the `patients` table. We want 83 to 93 inclusive.

4. Gender: female -> `gender = 'F'`

5. Stratification:
   a. ICU vs non-ICU: 
        - ICU: if the patient had at least one ICU stay (i.e., exists in `icustays` for that admission)
        - non-ICU: if the patient did not have an ICU stay (only hospital admission without ICU)

   b. LOS (length of stay): 
        - For hospital: we can get from `admissions` (dischtime - admittime) in days. But note: the question says "LOS", and in the context of the entire hospital stay? However, the stratification is by ICU vs non-ICU, so:
            - For ICU patients: we might consider the ICU LOS? But the question says "LOS" without specification. However, note the stratification: "LOS <8 vs >=8". 
            - The problem: the question does not specify whether LOS is hospital LOS or ICU LOS. But note the context: the population is defined by hospital admission (with heart failure) and then we split by ICU vs non-ICU. For non-ICU patients, we only have hospital LOS. For ICU patients, we have both hospital and ICU LOS. However, the question says "LOS" in the context of the entire admission? 

        Looking at the question: "stratified by ... LOS <8 vs ≥8". Since the non-ICU patients don't have ICU, it must be hospital LOS. So we use hospital LOS (from `admissions`).

        How to compute: 
            hospital_los = DATETIME_DIFF(dischtime, admittime, DAY)  -- but note: this might be fractional? We want in days, and then we can round? However, the question says <8 vs >=8, so we can use fractional days? But typically LOS is in days (integer). However, the problem says "median LOS", so we need the exact.

        Actually, the `admissions` table has `los`? Wait, no. But we can compute: 
            hospital_los = EXTRACT(DAY FROM (dischtime - admittime)) + ... but better to use TIMESTAMP_DIFF.

        However, note: the `admissions` table does not have a precomputed LOS. We have to compute.

        We'll compute: 
            hospital_los = TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0   -- to get fractional days? But the question says "median LOS", so we want the exact.

        But note: the question says "LOS <8 vs >=8", so we can use the same computed value for both the stratification and the median.

        However, the problem: the question says "stratified by ... LOS <8 vs >=8", meaning we are creating two groups: one with hospital LOS < 8 days and one with >=8 days.

        Important: This stratification is independent of the ICU status? Actually, the question says: "stratified by ICU vs non-ICU, LOS <8 vs ≥8, and comorbidity burden". So we have three stratification factors.

        So we will have 2 (ICU) * 2 (LOS) * 3 (comorbidity) = 12 groups.

   c. Comorbidity burden: 0-1, 2, >=3. We need to define a set of comorbidities.

        How to compute comorbidity burden? 
        We can use the Elixhauser comorbidity index. However, the question does not specify which comorbidities. But typically in such contexts, we use a standard set (like Elixhauser).

        Steps for Elixhauser:
          - We need to map ICD codes to Elixhauser comorbidities. There is a standard mapping (e.g., from Quan et al.).
          - We can use the `mimic-iv` package that has a comorbidity mapping, but in BigQuery we have to do it manually.

        However, note: the question says "comorbidity burden (0–1/2/≥3)", meaning we count the number of comorbidities (from a predefined set) that the patient has.

        We are not given a specific list, so we assume the standard Elixhauser comorbidities (which has 30 conditions). But note: the question does not specify, so we have to choose a standard.

        Since the problem is about heart failure, and we are excluding heart failure itself? Actually, comorbidity burden usually excludes the index condition? But the question does not specify. However, in standard practice, comorbidity indices (like Elixhauser) are designed to be used alongside the index condition.

        We'll use the Elixhauser comorbidities as defined in the literature. There is a mapping available in MIMIC-IV: 
          - The `mimic-iv` package has a comorbidity mapping, but we don't have that table. However, we can create a CTE that maps ICD codes to comorbidities.

        Alternatively, we can use the precomputed Elixhauser comorbidities from the `mimic-iv` package? But note: the problem says we are using the standard MIMIC-IV tables.

        Since we don't have a precomputed table, we have to create one. However, the problem does not specify which comorbidities, so we have to define a set.

        Given the complexity and the fact that the question does not specify, we will assume we are to use the standard Elixhauser comorbidities. But note: the problem says "comorbidity burden", and in the context of heart failure, common comorbidities include diabetes, CKD, etc.

        However, the question also asks for CKD and diabetes prevalence separately, so we don't want to double count? Actually, the comorbidity burden count should include diabetes and CKD as two of the conditions.

        Steps for comorbidity count:
          Step 1: For each patient, get all diagnoses (from `diagnoses_icd`).
          Step 2: Map each diagnosis to one or more Elixhauser comorbidities (using a mapping table we create in the query).
          Step 3: Count the distinct comorbidities (each comorbidity condition is counted once per patient, regardless of how many times it appears).

        But note: the Elixhauser comorbidities are 30 conditions. We don't want to list all 30 here? However, the problem does not specify, so we have to.

        Alternatively, we can use a precomputed mapping that is commonly used in MIMIC. There is a known mapping for Elixhauser in MIMIC-III, and it's similar for MIMIC-IV.

        However, due to the complexity and the fact that the problem does not specify the exact comorbidities, and given the constraints of the problem (we are to write a query), we might have to simplify.

        But note: the question says "comorbidity burden (0–1/2/≥3)", so we need a count of comorbidities. We must define which conditions.

        Given the time, and since the problem is about heart failure, and the question also asks for CKD and diabetes prevalence, it is likely that the comorbidity burden includes at least these two. But we need a standard set.

        We decide to use the 30 Elixhauser comorbidities as defined by Quan et al. (2005). However, implementing all 30 in SQL is lengthy.

        There is a known mapping for MIMIC-IV: 
          - We can use the mapping provided by the MIMIC team? But we don't have it in the schema.

        Alternatively, we can use a simplified approach: the problem might be expecting only a few key comorbidities? But the question says "comorbidity burden", which typically means a comprehensive set.

        Given the complexity, and since this is a common task, we note that there is a public BigQuery query for Elixhauser in MIMIC-IV. However, we are constrained to the tables provided.

        We decide to use a subset of comorbidities that are most relevant? But the problem does not specify.

        However, note: the question asks for CKD and diabetes prevalence separately, so we can assume that the comorbidity burden count includes these and others.

        We will have to create a mapping for the Elixhauser comorbidities. But to keep the query manageable, we will use a simplified version that includes the most common ones? Actually, the problem says "comorbidity burden", so we must be comprehensive.

        Given the constraints of the problem (we are to write a query that runs in BigQuery) and the fact that the Elixhauser mapping is long, we might have to rely on a precomputed table. But the problem states we only have the standard tables.

        Alternative: the problem might be referring to a simpler comorbidity index? However, the standard in critical care is Elixhauser.

        We found a reference: 
          https://github.com/MIT-LCP/mimic-code/blob/main/mimic-iv/comorbidity/sql/elixhauser_quan.sql

        We can adapt that for BigQuery.

        However, note: the problem does not require us to implement the entire Elixhauser, but we must do so to get the count.

        Steps for Elixhauser in MIMIC-IV:
          - We create a CTE that maps each ICD code to a set of comorbidities (using a CASE statement for each comorbidity condition).
          - Then, for each patient, we aggregate to see which comorbidities are present.

        But note: the mapping is long (about 30 conditions). We have to write it.

        However, the problem says "comorbidity burden (0–1/2/≥3)", so we only need the count. We don't need to know which ones.

        We can do:
          Step 1: For each patient, for each diagnosis, assign a flag for each comorbidity condition (if the diagnosis code falls into that condition).
          Step 2: Then, for the patient, we take the maximum flag per condition (so if any diagnosis code triggers the condition, it's 1).
          Step 3: Sum the flags to get the total count.

        But note: the Elixhauser conditions are mutually exclusive? No, they are not. A patient can have multiple.

        We'll create a CTE that for each patient and each comorbidity condition, we set a flag (1 if present, 0 otherwise). Then we sum the flags.

        However, the mapping is complex. We will use the standard mapping from the MIMIC code repository.

        Since the problem does not specify the exact comorbidities, and to keep the query within reasonable length, we will use a simplified version that includes only the conditions that are commonly used? But that would be arbitrary.

        Given the time, and because the problem is about heart failure, we note that common comorbidities in heart failure include:
          - Diabetes
          - CKD
          - Hypertension
          - COPD
          - etc.

        But the problem says "comorbidity burden", so we must use a standard.

        We decide to use the full Elixhauser mapping as provided in the MIMIC code repository. We will adapt the SQL from:
          https://github.com/MIT-LCP/mimic-code/blob/main/mimic-iv/comorbidity/sql/elixhauser_quan.sql

        However, note: that query is for MIMIC-IV and is written for PostgreSQL. We have to convert to BigQuery.

        But the problem: the query would be very long. And the problem says "generate the complete SQL query", so we have to include it.

        Alternatively, we can note that the problem might be expecting only a few key comorbidities? But the question says "comorbidity burden", which typically means a comprehensive set.

        Given the complexity, and since the problem is an example, we might be allowed to use a simplified set? However, the problem does not specify.

        We decide to use the following approach:

          We will create a CTE that lists all the comorbidity conditions we care about (the 30 Elixhauser conditions) and their ICD code mappings. But to keep the query from being too long, we will only include the conditions that are relevant for the age group? Actually, no.

        However, note: the problem says "comorbidity burden (0–1/2/≥3)", so we only need the count. We don't need to break down by condition.

        We can use a precomputed count? But we don't have it.

        We decide to implement the Elixhauser comorbidity count as per the standard mapping. We will write a CTE that for each diagnosis, assigns a set of comorbidities (using a long CASE statement). Then we aggregate per patient.

        But note: the mapping is long. We will have to write about 30 WHEN clauses.

        However, the problem does not specify which comorbidities, so we have to choose. We'll use the standard Elixhauser.

        Steps:

          We create a CTE `comorbidity_map` that for each `icd_code` and `icd_version`, we assign a bitmask or a set of condition flags? Actually, we can create 30 columns, but that is messy.

          Alternatively, we can create a CTE that for each diagnosis, we output multiple rows (one per comorbidity condition that it maps to). Then we can count distinct conditions per patient.

        We choose: for each diagnosis, we output a row for each comorbidity condition that the diagnosis belongs to. Then, for a patient, the number of distinct comorbidity conditions is the count.

        How to map: we can have a table of comorbidity conditions and their ICD code ranges. But we have to hardcode it.

        Given the complexity and the fact that the problem is about heart failure, and the question also asks for CKD and diabetes, we note that the comorbidity burden count should include these.

        We decide to use the following 5 comorbidities as a proxy? But that would not be standard.

        Alternatively, we can use the Charlson comorbidity index? But the question says "comorbidity burden" and the stratification is 0-1, 2, >=3, which is more granular than Charlson (which is a weighted index).

        Given the time, and because the problem is an example, we will assume that the comorbidity burden is defined by the presence of any of the following conditions (which are common in heart failure and also include the ones the question asks for):

          - Diabetes (with and without complications)
          - Chronic kidney disease (CKD)
          - Hypertension
          - Chronic pulmonary disease (COPD)
          - Peripheral vascular disease
          - Cerebrovascular disease
          - Dementia
          - Liver disease
          - Rheumatologic disease
          - Cancer (solid tumor and leukemia/lymphoma)
          - Metastatic cancer
          - AIDS

        But note: the Elixhauser has 30, but we can reduce to the most common? However, the problem does not specify.

        We decide to use the full Elixhauser mapping as per the standard. We will write a CTE that maps ICD codes to comorbidity conditions using a long CASE statement. We will base it on the MIMIC code repository.

        However, due to the length, and since this is a thought process, we will outline the steps and then in the actual query we will write a simplified version that includes only the conditions that are relevant for the age group? Actually, no.

        Given the constraints of the problem (we are to write a query that runs), and the fact that the full mapping is long, we note that the problem might be expecting only a few key conditions. But the question says "comorbidity burden", so we must be comprehensive.

        We found a BigQuery version of the Elixhauser mapping for MIMIC-IV: 
          https://github.com/MIT-LCP/mimic-code/blob/main/mimic-iv/comorbidity/sql/elixhauser_quan.sql

        We will adapt it to BigQuery.

        Steps from that query:

          They create a CTE `comorb` that for each condition, they assign a flag (0 or 1) for the patient.

          Then they sum the flags to get the count.

        We will do the same.

        However, the query is about 200 lines long. We have to include it.

        But note: the problem says "generate the complete SQL query", so we have to.

        Alternatively, we can note that the problem might be simplified for the purpose of this exercise? The problem says "comorbidity burden (0–1/2/≥3)", and we are only asked for three groups, so we don't need the exact conditions, just the count.

        We decide to use the following approach:

          We will create a CTE that computes the Elixhauser comorbidity count for each patient. We will use the standard mapping.

        However, to save space in the query, we will write a condensed version of the mapping. But note: the mapping is fixed.

        Given the time, and since this is a critical part, we will write the mapping for the comorbidities that are most likely to be present in elderly patients with heart failure. But that is arbitrary.

        We decide to use the following 10 conditions (which are common in heart failure and cover the ones the question asks for):

          1. Diabetes without complications
          2. Diabetes with complications
          3. Renal failure (CKD)
          4. Hypertension
          5. Chronic pulmonary disease
          6. Peripheral vascular disease
          7. Cerebrovascular disease
          8. Dementia
          9. Liver disease
          10. Cancer (solid tumor)

        But note: the question asks for CKD and diabetes prevalence, so we must have these two.

        However, the problem says "comorbidity burden", so we should include more.

        Given the complexity, and because the problem is an example, we will assume that the comorbidity burden is defined by the presence of any of the conditions in the Elixhauser list. We will use the full mapping as provided by the MIMIC code repository, but we will truncate it to the conditions that are relevant for the age group? Actually, no.

        We decide to use the full mapping. We will copy the mapping from the MIMIC code repository and convert to BigQuery.

        Steps for the mapping (from the MIMIC code repository):

          They have a long CASE statement for each condition.

        We will do:

          WITH elixhauser AS (
            SELECT 
              hadm_id,
              -- condition 1: congestive_heart_failure
              MAX(CASE WHEN ... THEN 1 ELSE 0 END) AS congestive_heart_failure,
              ... 30 conditions ...
            FROM diagnoses_icd
            GROUP BY hadm_id
          )

        But note: we are interested in the count of conditions (excluding heart failure? because the patient has heart failure as the index condition). However, in standard Elixhauser, heart failure is one of the conditions. But if we are studying heart failure, we might exclude it? 

        Actually, the Elixhauser index is designed to be used for any index condition, and it includes heart failure as one of the conditions. But if the patient has heart failure as the reason for admission, then we would count it. However, in comorbidity indices, the index condition is not excluded? Actually, comorbidities are conditions that coexist at the time of admission, so heart failure would be counted as a comorbidity even if it's the index condition? But that doesn't make sense.

        Clarification: In the context of heart failure as the index condition, we do not count heart failure as a comorbidity. So we should exclude it.

        How to handle: 
          - We are identifying patients with heart failure (so they have at least one diagnosis of heart failure). 
          - When computing comorbidities, we want to exclude heart failure.

        So in the comorbidity mapping, we will skip the heart failure condition.

        The Elixhauser condition for heart failure is "congestive_heart_failure". So we will not include that condition in our count.

        Therefore, we will compute the count of the other 29 conditions.

        Steps:

          We will create a CTE that for each admission (hadm_id), computes flags for 29 comorbidities (excluding congestive_heart_failure). Then we sum the flags to get the count.

        However, note: the patient might have multiple admissions? But the problem: we are studying a single admission (the one with heart failure). So we are grouping by admission.

        But note: the population is defined by having heart failure in a particular admission. So we are looking at one admission per patient? Actually, a patient might have multiple admissions with heart failure. The problem does not specify. We assume we are including every admission that meets the criteria.

        However, the question says "women 83-93 with heart failure", meaning per admission? Or per patient? 

        The problem: "stratified by ICU vs non-ICU" -> ICU status is per admission. Similarly, LOS is per admission. So we are analyzing per admission.

        Therefore, we will group by admission (hadm_id).

        Steps summary:

          Step 1: Identify admissions that meet:
            - Patient is female, age 83-93 (at the time of admission? note: `anchor_age` is the age at anchor_year, but we have `anchor_year_group` which is a range. However, we have `anchor_age` which is the age at the anchor year. But the admission might be in a different year.

          How to get age at admission?
            - We have `anchor_age` and `anchor_year` for the patient. 
            - The admission time: `admittime` (from `admissions` table).
            - We can compute: age_at_admission = EXTRACT(YEAR FROM admittime) - (anchor_year - anchor_age)

          But note: the `patients` table has `anchor_year` and `anchor_age`. The `anchor_year` is the year from which `anchor_age` is computed. So:

            age_at_admission = anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)

          However, this might not be exact because of the month. But for age range 83-93, we can approximate by year.

          Alternatively, we can use:

            age_at_admission = TIMESTAMP_DIFF(admittime, dob, YEAR)

          But wait: the `patients` table does not have `dob`! It has `anchor_age` and `anchor_year`, and `dod` (date of death). 

          How to compute age at admission?

            We know: 
              anchor_age = anchor_year - year_of_birth

            So: year_of_birth = anchor_year - anchor_age

            Then: age_at_admission = EXTRACT(YEAR FROM admittime) - (anchor_year - anchor_age)

          But this is approximate (ignores month). However, for age range 83-93, and since we are filtering by integer age, it might be acceptable.

          However, note: the problem says "83-93", so we want patients who were 83 to 93 years old at the time of admission.

          We can compute:

            age_at_admission = anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)

          But this might be off by one if the birthday hasn't occurred yet in the admission year.

          Given the complexity, and since MIMIC-IV does not provide exact date of birth, we have to use this approximation.

          Alternatively, we can use the `anchor_year_group` to get a range, but that is too broad.

          We decide to use:

            age_at_admission = anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year)

          And then filter: 83 <= age_at_admission <= 93

          But note: the `anchor_year` is the calendar year of the anchor date, and `admittime` is a timestamp. We can extract the year from `admittime`.

          Step 2: Heart failure diagnosis in that admission.

          Step 3: Gender = 'F'

        Step 4: For each admission, determine:
            - ICU status: if exists in `icustays` for that hadm_id -> then ICU, else non-ICU.
            - Hospital LOS: computed from `admissions` (dischtime - admittime) in days (as a number, fractional).
            - Comorbidity burden: count of Elixhauser comorbidities (excluding heart failure) for that admission.

        Step 5: Stratify:
            - ICU: two groups (ICU, non-ICU)
            - LOS: two groups (hospital_los < 8, hospital_los >= 8)
            - Comorbidity burden: three groups (0-1, 2, >=3)

        Step 6: For each group, report:
            - Mortality (%): hospital_expire_flag (from `admissions`) -> 1 if died in hospital, 0 otherwise. Then average * 100.
            - Median LOS: median of hospital_los (for the group)
            - CKD prevalence: we need to define CKD. We can use the same comorbidity mapping: if the patient has the renal failure condition (from Elixhauser), then 1, else 0. Then average * 100.
            - Diabetes prevalence: similarly, if the patient has diabetes (with or without complications) then 1, else 0.

        Note: The question asks for CKD and diabetes prevalence separately, so we don't use the comorbidity count for these, but we compute them independently.

        How to define CKD and diabetes?
          - We can use the same Elixhauser mapping: 
                CKD: corresponds to "renal_failure" in Elixhauser.
                Diabetes: corresponds to "diabetes_uncomplicated" and "diabetes_complicated" -> if either is present, then diabetes.

        But note: in the comorbidity burden count, we are already counting these as two separate conditions? Actually, diabetes uncomplicated and complicated are two separate conditions in Elixhauser? No, they are two conditions but we count them as one comorbidity? Actually, no: in the Elixhauser index, "diabetes uncomplicated" and "diabetes complicated" are two separate conditions, but for the purpose of diabetes prevalence, we want to know if the patient has diabetes (either uncomplicated or complicated).

        So for diabetes prevalence: 
            diabetes = 1 if (diabetes_uncomplicated = 1 OR diabetes_complicated = 1) else 0

        Similarly, for CKD: 
            ckd = 1 if renal_failure = 1 else 0

        However, note: the Elixhauser condition for renal failure is "renal_failure", which corresponds to CKD stage 3-5 or ESRD.

        So we can use that.

        Steps for the query:

          We will create several CTEs:

          CTE 1: admissions_with_heart_failure
            - Join `admissions` with `patients` to get gender and age.
            - Filter: gender='F', and age_at_admission between 83 and 93.
            - Join with `diagnoses_icd` to get heart failure diagnoses.
            - Group by hadm_id (to ensure we have at least one heart failure diagnosis per admission)

          CTE 2: icu_status
            - For each hadm_id, check if exists in `icustays` -> then ICU, else non-ICU.

          CTE 3: hospital_los
            - Compute from `admissions`: 
                  hospital_los = TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0   -- fractional days

          CTE 4: comorbidity_count (using Elixhauser, excluding heart failure)
            - We will compute flags for 29 comorbidities (all except congestive_heart_failure) for each admission.
            - Then sum the flags to get the count.

          CTE 5: ckd_flag and diabetes_flag
            - From the same comorbidity mapping, we can get:
                  ckd_flag = 1 if renal_failure = 1 else 0
                  diabetes_flag = 1 if (diabetes_uncomplicated=1 OR diabetes_complicated=1) else 0

          Then, we combine:

            SELECT 
              icu_status,
              CASE WHEN hospital_los < 8 THEN '<8' ELSE '>=8' END AS los_group,
              CASE 
                WHEN comorbidity_count <= 1 THEN '0-1'
                WHEN comorbidity_count = 2 THEN '2'
                ELSE '>=3'
              END AS comorbidity_group,
              AVG(hospital_expire_flag) * 100 AS mortality_pct,
              APPROX_QUANTILES(hospital_los, 100)[OFFSET(50)] AS median_los,  -- median
              AVG(ckd_flag) * 100 AS ckd_prevalence,
              AVG(diabetes_flag) * 100 AS diabetes_prevalence
            FROM ... 
            GROUP BY icu_status, los_group, comorbidity_group

        However, note: the hospital_expire_flag is in the `admissions` table.

        Important: We must ensure that we are only including admissions that meet the criteria (women 83-93 with heart failure).

        Steps in detail:

          Step 1: Get the base population (admissions with heart failure in women 83-93)

          WITH base AS (
            SELECT 
              a.hadm_id,
              p.gender,
              -- Compute age at admission
              p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
              a.hospital_expire_flag,
              a.admittime,
              a.dischtime
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
              ON a.subject_id = p.subject_id
            WHERE p.gender = 'F'
              AND p.anchor_age IS NOT NULL
              AND p.anchor_year IS NOT NULL
              AND a.admittime IS NOT NULL
              AND a.dischtime IS NOT NULL
              -- Filter age: 83 to 93
              AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 83 AND 93
              -- Now, we need to ensure there is at least one heart failure diagnosis in this admission
              AND EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
                WHERE d.hadm_id = a.hadm_id
                  AND (
                    (d.icd_version = 9 AND d.icd_code LIKE '428%')
                    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
                  )
              )
          )

          But note: the EXISTS might be inefficient. Alternatively, we can join and then group by hadm_id.

          We'll do:

          base AS (
            SELECT 
              a.hadm_id,
              p.gender,
              p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
              a.hospital_expire_flag,
              a.admittime,
              a.dischtime
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
              ON a.subject_id = p.subject_id
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
              ON a.hadm_id = d.hadm_id
            WHERE p.gender = 'F'
              AND p.anchor_age IS NOT NULL
              AND p.anchor_year IS NOT NULL
              AND a.admittime IS NOT NULL
              AND a.dischtime IS NOT NULL
              AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 83 AND 93
              AND (
                (d.icd_version = 9 AND d.icd_code LIKE '428%')
                OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
              )
            GROUP BY a.hadm_id, p.gender, age_at_admission, a.hospital_expire_flag, a.admittime, a.dischtime
          )

          However, note: the same admission might have multiple heart failure diagnoses, so we group by hadm_id.

          Step 2: ICU status

          icu_status AS (
            SELECT 
              hadm_id,
              CASE WHEN COUNT(stay_id) > 0 THEN 'ICU' ELSE 'non-ICU' END AS icu_status
            FROM `physionet-data.mimiciv_3_1_icu.icustays`
            GROUP BY hadm_id
          )

          But note: an admission might have multiple ICU stays? Then we still mark as ICU.

          Step 3:;