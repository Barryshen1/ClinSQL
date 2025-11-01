with pneumonia. The 44-year-old is just an example; we are to analyze the entire cohort of males aged 39-49 with pneumonia.

Important: The pneumonia types (aspiration vs community-acquired) are not explicitly defined in the database. We must use ICD codes to define them. We'll use the following ICD-10 codes (since MIMIC-IV uses ICD-10 for diagnoses_icd):

- Aspiration pneumonia: J69.0, J69.1, J69.2, J69.3, J69.4, J69.5, J69.6, J69.7, J69.8, J69.9
- Community-acquired pneumonia: J18.0, J18.1, J18.2, J18.3, J18.4, J18.5, J18.6, J18.7, J18.8, J18.9, J19.0, J19.1, J19.2, J19.3, J19.4, J19.5, J19.6, J19.7, J19.8, J19.9

We are to report:
- In-hospital mortality (%) by LOS (categorized as 1-3, 4-7, >=8 days) and day-1 ICU status (whether the patient was in the ICU on day 1 of hospitalization).
- Absolute and relative differences in mortality between the two pneumonia types within each LOS and ICU status group.
- Average comorbidity count (we can use the Charlson Comorbidity Index, but since it's not directly available, we might use the number of distinct ICD-10 codes in diagnoses_icd excluding the pneumonia diagnosis? Or use a predefined set of comorbidities? However, the question does not specify. Alternatively, we can use the number of distinct diagnoses in the admission excluding the pneumonia diagnosis as a proxy. But note: the question says "average comorbidity count", so we need to define comorbidities. Since the Charlson index is complex, we might use a simpler approach: count the number of distinct ICD-10 codes in diagnoses_icd for the admission that are not related to pneumonia. However, this is not standard. Alternatively, we can use the number of distinct ICD-10 codes in the admission that are in a predefined list of comorbidities (like the Charlson conditions). But without a predefined list, we might have to skip or use a different approach.

Given the complexity, and since the question does not specify, we can use the number of distinct ICD-10 codes in the admission (excluding the pneumonia diagnosis) as a proxy for comorbidity count. However, note that this includes all diagnoses, which might not be ideal. Alternatively, we can use the number of distinct ICD-10 codes in the admission that are not in the pneumonia list and not the primary diagnosis? But the question does not specify.

But note: the question asks for "average comorbidity count", and we are to report it along with the mortality. We can calculate the comorbidity count per patient and then average it per group.

However, to keep it manageable, we will define comorbidities as all ICD-10 codes in the admission that are not in the pneumonia list (aspiration or community-acquired) and not the primary diagnosis? But the primary diagnosis is not marked. Alternatively, we can use all diagnoses in the admission excluding the pneumonia diagnosis. But note: a patient might have multiple pneumonia diagnoses? We should exclude all pneumonia-related ICD codes.

So, for each patient, we will count the number of distinct ICD-10 codes in diagnoses_icd for that admission that are not in the list of aspiration or community-acquired pneumonia codes.

But note: the question says "comorbidity count", and comorbidities are typically chronic conditions. However, without a predefined list, we'll use this as a proxy.

Alternatively, we can use the Charlson Comorbidity Index, but that requires a complex mapping. Given the time, we'll use the proxy method.

Steps:

1. Identify the cohort: male patients aged 39-49 at the time of admission with pneumonia (either aspiration or community-acquired). We need to get the age at admission. We have `anchor_age` in patients, but that is the age at the time of the first event. We can use `admittime` and `dod` to compute age? But we have `anchor_age` and `anchor_year` which might be sufficient. However, to be precise, we can compute age from `admittime` and `dod`? But `dod` is date of death, not birth. We don't have birth date. We have `anchor_age` and `anchor_year` which are derived from the first event. We can use `anchor_age` and `anchor_year` to compute the birth year? But that might not be exact.

Alternatively, we can use the `admittime` and the `anchor_year` to compute the age at admission? But `anchor_year` is the year of the first event. We can compute the age at admission as:

  EXTRACT(YEAR FROM admittime) - anchor_year + anchor_age

But this is approximate. However, for a 44-year-old, we can filter by anchor_age between 39 and 49? But note: the patient might be 39 at the first event but 40 at admission. So it's better to use the anchor_age and anchor_year to compute the birth date approximately.

But MIMIC-IV documentation says: `anchor_age` is the age at the time of the first event in the database, and `anchor_year` is the year of that event. We can compute the birth year as `anchor_year - anchor_age`. Then, the age at admission is `EXTRACT(YEAR FROM admittime) - (anchor_year - anchor_age)`. But this is approximate.

Alternatively, we can use the `admittime` and the `dod`? But `dod` is date of death, not birth. We don't have birth date. So we have to rely on `anchor_age` and `anchor_year`.

We'll compute the birth year as `anchor_year - anchor_age`, then the age at admission as `EXTRACT(YEAR FROM admittime) - (anchor_year - anchor_age)`. Then filter for age between 39 and 49.

But note: the patient is 44, so we are including 39-49.

2. Pneumonia definition: we'll use the ICD-10 codes for aspiration and community-acquired pneumonia as above. We need to get the diagnosis from `diagnoses_icd` and join with `d_icd_diagnoses` to get the long title? But we only need the code. We'll filter `diagnoses_icd` for icd_code in the list of aspiration or community-acquired codes. We'll assign a type: 'aspiration' or 'community_acquired'.

3. In-hospital mortality: from `admissions`, `hospital_expire_flag` is 1 for in-hospital death.

4. LOS (length of stay): in days, from `admissions` (admittime to dischtime). We'll categorize:
   - 1-3 days
   - 4-7 days
   - >=8 days

5. Day-1 ICU status: whether the patient was in the ICU on day 1 of hospitalization. We can check if there is an ICU stay (`icustays`) that started on the same day as admission or within the first 24 hours? We can check if the `intime` of the ICU stay is within 24 hours of `admittime`. But note: a patient might have multiple ICU stays. We are interested in whether they were in the ICU on day 1. So we can check if there exists an ICU stay where `intime` is between `admittime` and `admittime + INTERVAL 1 DAY`.

6. Comorbidity count: for each patient, count the number of distinct ICD-10 codes in `diagnoses_icd` for that admission (hadm_id) that are not in the list of aspiration or community-acquired pneumonia codes. We'll exclude the pneumonia diagnosis.

7. Grouping: we need to group by pneumonia type (aspiration vs community-acquired), LOS category, and day-1 ICU status.

8. For each group, we want:
   - Number of patients
   - Number of deaths (in-hospital mortality)
   - Mortality rate (%)
   - Absolute difference in mortality between aspiration and community-acquired in the same LOS and ICU group? But the question says "absolute/relative differences". We need to compare aspiration vs community-acquired within each LOS and ICU group. So for each LOS and ICU group, we will have two rows (one for aspiration, one for community-acquired). Then we can compute the absolute difference (aspiration mortality - community-acquired mortality) and relative difference (absolute difference / community-acquired mortality) for each LOS and ICU group. But note: we are grouping by pneumonia type, so we need to do this per group.

   Alternatively, we can compute the mortality rates per group and then in a subsequent step compute the differences. But since we are grouping by pneumonia type, we can do:

   - For each LOS and ICU group, we can have two rows (aspiration and community-acquired). Then we can use window functions to compute the mortality for the other type? Or we can do a self-join? But that might be messy.

   Alternatively, we can compute the mortality rates per group and then use a pivot to have both in the same row? But the question asks for absolute and relative differences, so we need to show both types in the same row for comparison.

   We can do:

   Step 1: Compute the mortality rate per pneumonia type, LOS, ICU status.
   Step 2: Then, for each LOS and ICU group, we can pivot to have aspiration and community-acquired in the same row.

   But note: the question also asks for average comorbidity count per group (per pneumonia type, LOS, ICU status). So we need to compute that per group.

   So we can:

   - First, create a CTE for the cohort with all necessary information per patient.
   - Then, group by pneumonia_type, LOS_category, day1_icu_status to get:
        count_patients,
        sum(death) as deaths,
        avg(comorbidity_count) as avg_comorbidity_count
   - Then, compute mortality_rate = deaths / count_patients * 100

   - Then, for each LOS and ICU group, we want to have two rows (aspiration and community-acquired). Then we can use window functions to get the mortality rate for the other type in the same group.

   We can do:

   WITH grouped_data AS (
     ... group by pneumonia_type, LOS_category, day1_icu_status ...
   )
   SELECT 
     LOS_category,
     day1_icu_status,
     pneumonia_type,
     count_patients,
     deaths,
     mortality_rate,
     -- For the same LOS and ICU group, get the mortality_rate for the other pneumonia type
     MAX(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_rate END) OVER (PARTITION BY LOS_category, day1_icu_status) as mort_aspiration,
     MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_rate END) OVER (PARTITION BY LOS_category, day1_icu_status) as mort_community_acquired
   FROM grouped_data

   Then, for each row, we can compute:
     absolute_diff = mort_aspiration - mort_community_acquired   [if pneumonia_type is aspiration, then this is the difference; if community_acquired, then it's negative? But we want the difference between aspiration and community-acquired, so we can compute it once per group and then display in both rows? Or we can do:

   Instead, we can pivot to have one row per LOS and ICU group with both pneumonia types:

   SELECT 
     LOS_category,
     day1_icu_status,
     MAX(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_rate END) as mort_aspiration,
     MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_rate END) as mort_community_acquired,
     AVG(CASE WHEN pneumonia_type = 'aspiration' THEN avg_comorbidity_count END) as avg_comorbidity_aspiration,
     AVG(CASE WHEN pneumonia_type = 'community_acquired' THEN avg_comorbidity_count END) as avg_comorbidity_community_acquired
   FROM grouped_data
   GROUP BY LOS_category, day1_icu_status

   But note: the grouped_data already has one row per pneumonia_type, so we can do:

   WITH grouped_data AS (
     ... 
   ),
   pivoted AS (
     SELECT 
       LOS_category,
       day1_icu_status,
       MAX(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_rate END) as mort_aspiration,
       MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_rate END) as mort_community_acquired,
       MAX(CASE WHEN pneumonia_type = 'aspiration' THEN count_patients END) as count_aspiration,
       MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN count_patients END) as count_community_acquired,
       MAX(CASE WHEN pneumonia_type = 'aspiration' THEN deaths END) as deaths_aspiration,
       MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN deaths END) as deaths_community_acquired,
       MAX(CASE WHEN pneumonia_type = 'aspiration' THEN avg_comorbidity_count END) as avg_comorbidity_aspiration,
       MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN avg_comorbidity_count END) as avg_comorbidity_community_acquired
     FROM grouped_data
     GROUP BY LOS_category, day1_icu_status
   )
   SELECT 
     LOS_category,
     day1_icu_status,
     mort_aspiration,
     mort_community_acquired,
     (mort_aspiration - mort_community_acquired) as absolute_diff,
     (mort_aspiration - mort_community_acquired) / NULLIF(mort_community_acquired, 0) as relative_diff,
     avg_comorbidity_aspiration,
     avg_comorbidity_community_acquired
   FROM pivoted

   But note: we also need the counts? The question asks for mortality (%) and comorbidity count. We can include the counts in the output.

   Alternatively, we can keep the grouped_data and then compute the differences per group using window functions without pivoting, but then we have two rows per group. We can do:

   WITH grouped_data AS (
     ... 
   ),
   with_diff AS (
     SELECT 
       *,
       mort_aspiration - mort_community_acquired as absolute_diff,
       (mort_aspiration - mort_community_acquired) / NULLIF(mort_community_acquired, 0) as relative_diff
     FROM (
       SELECT 
         *,
         MAX(CASE WHEN pneumonia_type = 'aspiration' THEN mortality_rate END) OVER (PARTITION BY LOS_category, day1_icu_status) as mort_aspiration,
         MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN mortality_rate END) OVER (PARTITION BY LOS_category, day1_icu_status) as mort_community_acquired
       FROM grouped_data
     )
   )
   SELECT 
     LOS_category,
     day1_icu_status,
     pneumonia_type,
     count_patients,
     deaths,
     mortality_rate,
     absolute_diff,
     relative_diff,
     avg_comorbidity_count
   FROM with_diff

   But then we have two rows per LOS and ICU group, and the absolute_diff and relative_diff are the same for both rows? And we have the comorbidity count per pneumonia type.

   The question does not specify the exact output format, but we need to report absolute and relative differences. We can choose either format. I think the pivoted format is clearer.

   However, the question says "by LOS (1–3/4–7/≥8 days) and day-1 ICU status", so we are grouping by these three. We can output one row per LOS and ICU group with both pneumonia types and the differences.

   We'll do the pivoted format.

9. Edge cases:
   - Patients without ICU stay: day1_icu_status = false.
   - Patients without any diagnosis? But we are filtering by pneumonia, so they must have at least one pneumonia diagnosis.
   - Patients with multiple pneumonia diagnoses? We are assigning the type based on the presence of any aspiration or community-acquired code. But note: a patient might have both? We need to decide: if a patient has both, we might assign to one? Or we can have a third category? But the question is aspiration vs community-acquired. We can assign based on the first diagnosis? Or we can have a rule: if aspiration is present, then aspiration; else if community-acquired, then community-acquired. But what if both? We can assign to aspiration? Or we can exclude? But the question doesn't specify. We'll assign the type as follows: if the patient has any aspiration pneumonia code, then type='aspiration'; else if they have any community-acquired, then type='community_acquired'. If both, we assign 'aspiration'. We can also note that in the reasoning.

   Alternatively, we can have a separate category for both, but the question only asks for two types. So we'll do:

     CASE 
        WHEN aspiration_pneumonia THEN 'aspiration'
        WHEN community_acquired_pneumonia THEN 'community_acquired'
        ELSE NULL 
     END

   But if both, we assign aspiration? Or we can do:

     CASE 
        WHEN aspiration_pneumonia AND community_acquired_pneumonia THEN 'both'
        WHEN aspiration_pneumonia THEN 'aspiration'
        WHEN community_acquired_pneumonia THEN 'community_acquired'
        ELSE NULL 
     END

   But the question doesn't mention both. We'll assume that a patient can have only one type? Or we can assign the type based on the primary diagnosis? But we don't have primary diagnosis. We'll do:

     We'll define:
        aspiration: if any diagnosis_icd code in the aspiration list for that admission.
        community_acquired: if any diagnosis_icd code in the community-acquired list for that admission.

     Then, if both, we assign to aspiration? Or we can create a third group? But the question asks for two types. We'll assign to aspiration if aspiration is present, regardless of community-acquired. This is arbitrary. Alternatively, we can exclude patients with both? But that might be rare.

   We'll do: if aspiration is present, then type='aspiration'; else if community_acquired is present, then type='community_acquired'. If both, we assign 'aspiration'. We can note this in the reasoning.

   - Comorbidity count: we are excluding the pneumonia diagnosis. But note: a patient might have multiple pneumonia diagnoses? We are excluding all codes in the pneumonia list. So we count distinct ICD-10 codes that are not in the pneumonia list.

   - LOS: we use `admittime` and `dischtime` from `admissions`. We compute LOS in days: `DATE_DIFF(dischtime, admittime, DAY)`. But note: if the patient died in the hospital, `dischtime` is the time of death? Actually, `dischtime` is the discharge time, and if the patient died, it's the time of death? According to the schema, `dischtime` is the time of discharge or death. So we can use `dischtime`.

   - Day-1 ICU status: we check if there is an ICU stay that started within the first 24 hours of admission. We can do:

        EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_icu.icustays` i
          WHERE i.subject_id = a.subject_id
            AND i.hadm_id = a.hadm_id
            AND i.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
        )

   - We must consider that a patient might have multiple admissions? But we are filtering by age at admission, so we are looking at one admission per patient? But a patient might have multiple admissions. We are to analyze the cohort of admissions (hadm_id) for male 39-49 with pneumonia. So we are looking at each admission that meets the criteria.

   - We must filter for the correct admission: we are using `admissions` and `patients` to get the age.

   - We must ensure we are using the correct datasets: `physionet-data.mimiciv_3_1_hosp` and `physionet-data.mimiciv_3_1_icu`.

10. Tables to use:
    - `patients` for age and gender.
    - `admissions` for admission details, mortality, LOS.
    - `diagnoses_icd` for pneumonia diagnosis and comorbidity count.
    - `icustays` for ICU status on day 1.

11. Steps in the query:

    Step 1: Get the cohort of admissions for male patients aged 39-49 at admission with pneumonia.

    We'll compute the birth year as `anchor_year - anchor_age`, then the age at admission as `EXTRACT(YEAR FROM admittime) - (anchor_year - anchor_age)`. But note: this is approximate. Alternatively, we can use the `admittime` and `anchor_year` and `anchor_age` to compute the birth date as `DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR)`, then compute the age at admission as `DATE_DIFF(admittime, birth_date, YEAR)`. But this is still approximate because we don't know the exact birth date.

    We'll do:

        birth_date_approx = DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR)

    Then age at admission = `DATE_DIFF(admittime, birth_date_approx, YEAR)`

    But note: `DATE_DIFF` with YEAR returns the number of full years. This is acceptable.

    Step 2: Identify pneumonia type.

    Step 3: Compute LOS in days.

    Step 4: Check for ICU stay on day 1.

    Step 5: Compute comorbidity count per admission (excluding pneumonia diagnoses).

    Step 6: Group by pneumonia_type, LOS_category, day1_icu_status.

    Step 7: Pivot to have both pneumonia types per LOS and ICU group.

    Step 8: Compute absolute and relative differences.

    Step 9: Output.

    We'll break into CTEs.

    Note: We must be cautious of performance. We are filtering a large dataset.

    Let's define the pneumonia ICD-10 codes as arrays.

    We'll use:

        ASPIRATION_PNEUMONIA_CODES = ['J69.0', 'J69.1', ...]
        COMMUNITY_ACQUIRED_PNEUMONIA_CODES = ['J18.0', ...]

    But in BigQuery, we can use arrays or a CASE statement with IN.

    We'll use:

        SELECT 
          ...,
          CASE 
            WHEN EXISTS (SELECT 1 FROM UNNEST(ASPIRATION_PNEUMONIA_CODES) AS code WHERE d.icd_code = code) THEN TRUE
            ELSE FALSE
          END AS has_aspiration_pneumonia

    But we can do:

        SELECT 
          ...,
          CASE 
            WHEN d.icd_code IN UNNEST(ASPIRATION_PNEUMONIA_CODES) THEN 'aspiration'
            WHEN d.icd_code IN UNNEST(COMMUNITY_ACQUIRED_PNEUMONIA_CODES) THEN 'community_acquired'
          END AS pneumonia_type

    But we need to assign one type per admission. We can use:

        SELECT 
          a.hadm_id,
          CASE 
            WHEN COUNT_IF(d.icd_code IN UNNEST(ASPIRATION_PNEUMONIA_CODES)) > 0 THEN 'aspiration'
            WHEN COUNT_IF(d.icd_code IN UNNEST(COMMUNITY_ACQUIRED_PNEUMONIA_CODES)) > 0 THEN 'community_acquired'
            ELSE NULL 
          END AS pneumonia_type

    But note: we are grouping by hadm_id, so we can do:

        WITH diagnoses AS (
          SELECT 
            hadm_id,
            icd_code,
            CASE 
              WHEN icd_code IN UNNEST(ASPIRATION_PNEUMONIA_CODES) THEN 'aspiration'
              WHEN icd_code IN UNNEST(COMMUNITY_ACQUIRED_PNEUMONIA_CODES) THEN 'community_acquired'
              ELSE NULL 
            END AS pneumonia_type
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        ),
        admission_diagnoses AS (
          SELECT 
            hadm_id,
            MAX(pneumonia_type) AS pneumonia_type   -- if both, we get one arbitrarily? We want to assign aspiration if present, then community_acquired. But MAX might not be aspiration if community_acquired is present? We can use:
            -- Instead, we can do:
            CASE 
              WHEN BOOL_OR(pneumonia_type = 'aspiration') THEN 'aspiration'
              WHEN BOOL_OR(pneumonia_type = 'community_acquired') THEN 'community_acquired'
              ELSE NULL 
            END AS pneumonia_type
          FROM diagnoses
          GROUP BY hadm_id
        )

    But note: we are only interested in admissions that have at least one pneumonia diagnosis. So we can filter.

    Alternatively, we can do:

        SELECT 
          hadm_id,
          CASE 
            WHEN SUM(CASE WHEN icd_code IN UNNEST(ASPIRATION_PNEUMONIA_CODES) THEN 1 ELSE 0 END) > 0 THEN 'aspiration'
            WHEN SUM(CASE WHEN icd_code IN UNNEST(COMMUNITY_ACQUIRED_PNEUMONIA_CODES) THEN 1 ELSE 0 END) > 0 THEN 'community_acquired'
            ELSE NULL 
          END AS pneumonia_type
        FROM diagnoses_icd
        GROUP BY hadm_id

    This is efficient.

    Step 5: Comorbidity count per admission: count distinct icd_code in diagnoses_icd for the admission that are not in the pneumonia lists.

        SELECT 
          hadm_id,
          COUNT(DISTINCT icd_code) AS total_diagnoses,
          COUNT(DISTINCT CASE WHEN icd_code NOT IN UNNEST(ASPIRATION_PNEUMONIA_CODES) AND icd_code NOT IN UNNEST(COMMUNITY_ACQUIRED_PNEUMONIA_CODES) THEN icd_code END) AS comorbidity_count
        FROM diagnoses_icd
        GROUP BY hadm_id

    But note: we are excluding the pneumonia diagnoses. However, we are counting distinct codes, so if a patient has multiple pneumonia codes, we exclude all of them.

    Step 6: ICU status on day 1: we can do a left join to icustays and check if there is any stay that started within the first 24 hours.

        SELECT 
          a.hadm_id,
          CASE 
            WHEN EXISTS (
              SELECT 1 
              FROM `physionet-data.mimiciv_3_1_icu.icustays` i
              WHERE i.hadm_id = a.hadm_id
                AND i.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
            ) THEN TRUE
            ELSE FALSE 
          END AS day1_icu
        FROM admissions a

    But note: a patient might have multiple ICU stays, but we only care if at least one started in the first 24 hours.

    Step 7: Combine.

    We'll create a CTE for the base cohort:

        base_cohort AS (
          SELECT 
            a.hadm_id,
            a.subject_id,
            a.admittime,
            a.dischtime,
            a.hospital_expire_flag,
            -- Compute age at admission
            DATE_DIFF(a.admittime, 
                      DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR),
                      YEAR) AS age_at_admission,
            p.gender,
            -- LOS in days
            DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
            -- Pneumonia type from diagnoses_icd
            (SELECT 
               CASE 
                 WHEN SUM(CASE WHEN d.icd_code IN UNNEST(ASPIRATION_PNEUMONIA_CODES) THEN 1 ELSE 0 END) > 0 THEN 'aspiration'
                 WHEN SUM(CASE WHEN d.icd_code IN UNNEST(COMMUNITY_ACQUIRED_PNEUMONIA_CODES) THEN 1 ELSE 0 END) > 0 THEN 'community_acquired'
                 ELSE NULL 
               END 
             FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
             WHERE d.hadm_id = a.hadm_id
            ) AS pneumonia_type,
            -- Comorbidity count: distinct diagnoses excluding pneumonia codes
            (SELECT 
               COUNT(DISTINCT d.icd_code) 
             FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
             WHERE d.hadm_id = a.hadm_id
               AND d.icd_code NOT IN UNNEST(ASPIRATION_PNEUMONIA_CODES)
               AND d.icd_code NOT IN UNNEST(COMMUNITY_ACQUIRED_PNEUMONIA_CODES)
            ) AS comorbidity_count,
            -- Day1 ICU status
            (SELECT 
               CASE 
                 WHEN EXISTS (
                   SELECT 1 
                   FROM `physionet-data.mimiciv_3_1_icu.icustays` i
                   WHERE i.hadm_id = a.hadm_id
                     AND i.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
                 ) THEN TRUE
                 ELSE FALSE 
               END
            ) AS day1_icu
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
          INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
            ON a.subject_id = p.subject_id
          WHERE p.gender = 'M'
            AND DATE_DIFF(a.admittime, 
                         DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR),
                         YEAR) BETWEEN 39 AND 49
            AND a.hospital_expire_flag IS NOT NULL   -- ensure we have mortality status
        )

    But note: the pneumonia_type subquery might be inefficient. We can do a separate CTE for diagnoses and then join.

    Alternatively, we can do:

        WITH 
        aspiration_codes AS (SELECT * FROM UNNEST(['J69.0','J69.1',...]) AS code),
        community_acquired_codes AS (SELECT * FROM UNNEST(['J18.0',...]) AS code),
        diagnoses AS (
          SELECT 
            hadm_id,
            icd_code,
            CASE 
              WHEN icd_code IN (SELECT code FROM aspiration_codes) THEN 'aspiration'
              WHEN icd_code IN (SELECT code FROM community_acquired_codes) THEN 'community_acquired'
              ELSE NULL 
            END AS pneumonia_type
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        ),
        admission_diagnoses AS (
          SELECT 
            hadm_id,
            MAX(pneumonia_type) AS pneumonia_type   -- This doesn't work because if both, we get one arbitrarily? We want to assign aspiration if present, then community_acquired. We can do:
            -- Instead, we can use:
            CASE 
              WHEN BOOL_OR(pneumonia_type = 'aspiration') THEN 'aspiration'
              WHEN BOOL_OR(pneumonia_type = 'community_acquired') THEN 'community_acquired'
              ELSE NULL 
            END AS pneumonia_type
          FROM diagnoses
          GROUP BY hadm_id
        ),
        comorbidity_counts AS (
          SELECT 
            hadm_id,
            COUNT(DISTINCT icd_code) AS total_diagnoses,
            COUNT(DISTINCT CASE WHEN icd_code NOT IN (SELECT code FROM aspiration_codes) AND icd_code NOT IN (SELECT code FROM community_acquired_codes) THEN icd_code END) AS comorbidity_count
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
          GROUP BY hadm_id
        ),
        icu_day1 AS (
          SELECT 
            a.hadm_id,
            CASE 
              WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_icu.icustays` i
                WHERE i.hadm_id = a.hadm_id
                  AND i.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
              ) THEN TRUE
              ELSE FALSE 
            END AS day1_icu
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
        ),
        base_cohort AS (
          SELECT 
            a.hadm_id,
            a.subject_id,
            a.admittime,
            a.dischtime,
            a.hospital_expire_flag,
            DATE_DIFF(a.admittime, 
                      DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR),
                      YEAR) AS age_at_admission,
            p.gender,
            DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
            ad.pneumonia_type,
            cc.comorbidity_count,
            i.day1_icu
          FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
          INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
            ON a.subject_id = p.subject_id
          LEFT JOIN admission_diagnoses ad 
            ON a.hadm_id = ad.hadm_id
          LEFT JOIN comorbidity_counts cc 
            ON a.hadm_id = cc.hadm_id
          LEFT JOIN icu_day1 i 
            ON a.hadm_id = i.hadm_id
          WHERE p.gender = 'M'
            AND DATE_DIFF(a.admittime, 
                         DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR),
                         YEAR) BETWEEN 39 AND 49
            AND a.hospital_expire_flag IS NOT NULL
            AND ad.pneumonia_type IS NOT NULL   -- only admissions with pneumonia
        )

    But note: the comorbidity_count might be NULL if there are no non-pneumonia diagnoses? We can use COALESCE to 0.

    Also, we must ensure that the pneumonia_type is not null.

    Step 8: Categorize LOS:

        CASE 
          WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
          WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
          WHEN los_days >= 8 THEN '>=8'
          ELSE 'Unknown' 
        END AS los_category

    Step 9: Group by pneumonia_type, los_category, day1_icu.

        grouped_data AS (
          SELECT 
            pneumonia_type,
            los_category,
            day1_icu,
            COUNT(*) AS count_patients,
            SUM(CAST(hospital_expire_flag AS INT)) AS deaths,
            AVG(comorbidity_count) AS avg_comorbidity_count
          FROM base_cohort
          GROUP BY pneumonia_type, los_category, day1_icu
        )

    Step 10: Pivot to have both pneumonia types per LOS and ICU group.

        pivoted_data AS (
          SELECT 
            los_category,
            day1_icu,
            MAX(CASE WHEN pneumonia_type = 'aspiration' THEN deaths END) AS deaths_aspiration,
            MAX(CASE WHEN pneumonia_type = 'aspiration' THEN count_patients END) AS count_aspiration,
            MAX(CASE WHEN pneumonia_type = 'aspiration' THEN avg_comorbidity_count END) AS avg_comorbidity_aspiration,
            MAX(CASE WHEN pneumonia_type = 'aspiration' THEN deaths / NULLIF(count_patients,0) * 100 END) AS mort_aspiration,
            MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN deaths END) AS deaths_community_acquired,
            MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN count_patients END) AS count_community_acquired,
            MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN avg_comorbidity_count END) AS avg_comorbidity_community_acquired,
            MAX(CASE WHEN pneumonia_type = 'community_acquired' THEN deaths / NULLIF(count_patients,0) * 100 END) AS mort_community_acquired
          FROM grouped_data
          GROUP BY los_category, day1_icu
        )

    Step 11: Compute differences.

        SELECT 
          los_category,
          day1_icu,
          mort_aspiration,
          mort_community_acquired,
          (mort_aspiration - mort_community_acquired) AS absolute_diff,
          (mort_aspiration - mort_community_acquired) / NULLIF(mort_community_acquired, 0) AS relative_diff,
          avg_comorbidity_aspiration,
          avg_comorbidity_community_acquired,
          count_aspiration,
          count_community_acquired,
          deaths_aspiration,
          deaths_community_acquired
        FROM;