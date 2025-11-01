with sepsis. We need to analyze male ICU patients aged 90-100 with sepsis.
- We are to compute the SD of diagnostic utilization in the first 24h. Diagnostic utilization likely refers to the number of diagnostic tests (labs, microbiology, etc.) ordered in the first 24 hours of ICU stay.
- Additionally, we need p75, p95, in-hospital mortality %, average LOS (length of stay), and admissions versus overall ICU. 
  - "Admissions versus overall ICU" might mean the proportion of ICU admissions that are sepsis-related? Or perhaps the ratio of sepsis admissions to total ICU admissions? Given the context, it likely refers to the percentage of ICU admissions that are for sepsis among this age/gender group. But note: the question says "admissions versus overall ICU", which might be ambiguous. However, in the context of the cohort, we are already filtering for sepsis, so we might need to compare with the entire ICU population? But the question asks for the cohort of sepsis patients. Let me re-read: "Among male ICU patients age 90–100 with sepsis, what is the SD of diagnostic utilization in the first 24h? Also report p75, p95, in‑hospital mortality %, average LOS, and admissions versus overall ICU."

  - "Admissions versus overall ICU" could mean the ratio of the number of admissions (for sepsis) to the total ICU admissions in the same age/gender group? But note that the cohort is already defined as sepsis patients. Alternatively, it might be a typo and they want the ICU admission rate? But the question says "admissions versus overall ICU", which is unclear. Given the ambiguity, I will interpret it as the proportion of ICU admissions (in the same age/gender group) that are for sepsis. However, the cohort is defined as sepsis patients, so we are only looking at sepsis patients. But the question asks for "admissions versus overall ICU", which might be a separate metric. 

  - Let me break down the required outputs:
    1. SD of diagnostic utilization in the first 24h (for the cohort of sepsis patients).
    2. p75 and p95 of diagnostic utilization (same cohort).
    3. in-hospital mortality % (for the cohort).
    4. average LOS (length of stay in ICU? or hospital? The question says "average LOS", and in ICU context, LOS often refers to ICU length of stay. But note: the patient is in ICU, and the question mentions "ICU patient". However, the mortality is in-hospital, so LOS might be hospital LOS? But the question says "average LOS", without specifying. Given the context, I think ICU LOS is more relevant, but we have both. Let me see: the question says "average LOS", and in the ICU module, we have `icustays` with `los` (ICU length of stay). Also, in `admissions` we have `dischtime` and `admittime` for hospital LOS. The question does not specify, but since the patient is in ICU, and we are looking at ICU patients, I think ICU LOS is intended. However, the mortality is in-hospital, so we might need hospital LOS for mortality? But the LOS metric is separate. I will assume ICU LOS for the LOS metric.

    5. admissions versus overall ICU: I think this means the proportion of ICU admissions (in the same age/gender group) that are for sepsis. But note: the cohort is already sepsis patients, so we are only looking at sepsis. Alternatively, it might be the ratio of the number of sepsis admissions to the total ICU admissions in the same age/gender group. This would require two counts: one for sepsis admissions and one for total ICU admissions in the age/gender group.

  - However, the question says "Among male ICU patients age 90–100 with sepsis", so the cohort is defined. The "admissions versus overall ICU" might be a separate metric that is not for the cohort but for the entire ICU population? But that doesn't make sense because it says "also report" for the same cohort. Alternatively, it might be a typo and they want the ICU admission rate? But I think the intended meaning is the proportion of ICU admissions (in the same age/gender group) that are for sepsis. So we need to compute:
      - For the cohort: sepsis patients (age 90-100, male, ICU) -> count of admissions (each hadm_id is an admission)
      - For the denominator: total ICU admissions (age 90-100, male) regardless of sepsis.

  - But note: the question says "admissions versus overall ICU", which might be interpreted as the ratio of the number of admissions (for sepsis) to the total ICU admissions in the same group. So we can compute: (number of sepsis admissions) / (total ICU admissions in age 90-100 male).

- Steps:
  1. Identify the cohort: male ICU patients aged 90-100 with sepsis.
      - From `patients` and `icustays` for age and gender.
      - Sepsis: we need to define sepsis. In MIMIC-IV, sepsis is often identified by ICD codes. We can use `diagnoses_icd` with ICD-10 codes for sepsis (e.g., A40, A41, etc.). But note: the question says "with sepsis", so we need to define sepsis. We can use the following ICD-10 codes for sepsis: 
          - A40: Sepsis, unspecified
          - A40.0: Sepsis due to other specified organisms
          - A40.1: Sepsis due to Staphylococcus aureus
          - A40.2: Sepsis due to Streptococcus
          - A40.3: Sepsis due to other streptococci
          - A40.4: Sepsis due to Escherichia coli
          - A40.5: Sepsis due to other gram-negative bacteria
          - A40.6: Sepsis due to other specified organisms
          - A40.7: Sepsis due to unspecified organism
          - A40.8: Sepsis due to multiple organisms
          - A40.9: Sepsis, unspecified
          - A41: Severe sepsis
          - A41.0: Severe sepsis due to other specified organisms
          - A41.1: Severe sepsis due to Staphylococcus aureus
          - A41.2: Severe sepsis due to Streptococcus
          - A41.3: Severe sepsis due to other streptococci
          - A41.4: Severe sepsis due to Escherichia coli
          - A41.5: Severe sepsis due to other gram-negative bacteria
          - A41.6: Severe sepsis due to other specified organisms
          - A41.7: Severe sepsis due to unspecified organism
          - A41.8: Severe sepsis due to multiple organisms
          - A41.9: Severe sepsis, unspecified
          - R65.20: Sepsis, unspecified organism
          - R65.21: Sepsis, Staphylococcus aureus
          - R65.22: Sepsis, Streptococcus
          - R65.23: Sepsis, other streptococci
          - R65.24: Sepsis, Escherichia coli
          - R65.25: Sepsis, other gram-negative bacteria
          - R65.26: Sepsis, other specified organisms
          - R65.27: Sepsis, unspecified organism
          - R65.28: Sepsis, multiple organisms
          - R65.29: Sepsis, unspecified
          - R65.30: Severe sepsis, unspecified organism
          - R65.31: Severe sepsis, Staphylococcus aureus
          - R65.32: Severe sepsis, Streptococcus
          - R65.33: Severe sepsis, other streptococci
          - R65.34: Severe sepsis, Escherichia coli
          - R65.35: Severe sepsis, other gram-negative bacteria
          - R65.36: Severe sepsis, other specified organisms
          - R65.37: Severe sepsis, unspecified organism
          - R65.38: Severe sepsis, multiple organisms
          - R65.39: Severe sepsis, unspecified
        However, note that ICD-10 codes for sepsis are complex. Alternatively, we can use the MIMIC-IV sepsis definition from the MIMIC-IV documentation? But the question does not specify. Since this is a common task, we can use the ICD-10 codes for sepsis as above. But note: the `diagnoses_icd` table has `icd_version` which should be 10 for ICD-10. We'll filter for icd_version=10 and icd_code in the list above.

      - Alternatively, we can use the `sepsis3` table from the MIMIC-IV-ED module? But the question does not mention ED, and we are using HOSP and ICU. The `sepsis3` table is in the `physionet-data.mimiciv_3_1_ed` dataset, which is not included in the constraints. So we cannot use that. Therefore, we must rely on ICD codes.

      - We'll use the `diagnoses_icd` table and filter for ICD-10 codes that indicate sepsis. We'll create a list of relevant codes.

  2. For each ICU stay in the cohort, we need to count the number of diagnostic tests in the first 24 hours.
      - Diagnostic tests: labs (labevents), microbiology (microbiologyevents), and possibly others? The question says "diagnostic utilization", which likely includes lab tests and microbiology. We might also consider imaging? But the MIMIC-IV ICU module does not have a direct table for imaging. The `chartevents` table has some measurements, but they are more for monitoring. The `hcpcsevents` table has billing codes, which might include imaging, but that is not diagnostic utilization per se. Given the ambiguity, I will assume diagnostic utilization refers to lab tests and microbiology tests.

      - We'll consider:
          - `labevents`: for lab tests. We need to count the number of lab events per ICU stay in the first 24 hours.
          - `microbiologyevents`: for microbiology tests. Similarly, count per ICU stay in the first 24 hours.

      - We'll combine these counts? Or treat them separately? The question says "diagnostic utilization", which might be a single metric. We can sum the counts from both sources.

      - Steps for diagnostic utilization:
          - For each ICU stay (from `icustays`), we have `intime` (start of ICU stay).
          - First 24 hours: from `intime` to `intime + 24 hours`.
          - Count labevents: where `charttime` between `intime` and `intime + 24 hours`, and `hadm_id` matches the ICU stay's `hadm_id` (since each ICU stay is within an admission).
          - Similarly for microbiologyevents: `charttime` between `intime` and `intime + 24 hours`.
          - Then, for each ICU stay, we can compute:
                diagnostic_utilization = (count of labevents) + (count of microbiologyevents)

      - But note: a single lab test might have multiple rows (e.g., different components). We are counting events, so that's fine.

  3. We need to compute:
      - SD of diagnostic_utilization for the cohort.
      - p75 and p95 of diagnostic_utilization.
      - in-hospital mortality %: from `admissions` table, `hospital_expire_flag` for the admission. We can join `icustays` to `admissions` on `hadm_id` and `subject_id` to get the mortality flag.
      - average LOS: ICU length of stay, which is in `icustays` as `los` (in hours). We can convert to days? But the question doesn't specify. We'll report in hours or days? Since LOS is often in days, we can convert to days by dividing by 24. But the question says "average LOS", so we can report in days for clarity. Alternatively, we can report in hours as stored. I think days is more common. We'll compute AVG(los)/24 to get days.

      - admissions versus overall ICU: as discussed, we need two counts:
          - Count1: number of ICU admissions (stays) in the cohort (i.e., sepsis patients, age 90-100, male).
          - Count2: total number of ICU admissions (stays) for age 90-100, male (regardless of sepsis).
          - Then, the ratio = Count1 / Count2.

  4. Edge cases:
      - A patient might have multiple ICU stays? We are using `icustays` so each row is a stay. We need to consider each stay as an independent admission? The question says "admissions", so we are counting ICU admissions (stays). But note: one hospital admission might have multiple ICU stays? Yes, but the `icustays` table has one row per stay. We are counting stays, not patients. The question says "admissions", which in ICU context often means ICU admissions (stays). So we'll count stays.

      - For the cohort, we are filtering by age and gender. Age: we have `anchor_age` in `patients`? But `anchor_age` is the age at the time of the first event in the database. We need age at ICU admission. We can compute age at `intime` from `anchor_year` and `anchor_year_group`? But that is approximate. Alternatively, we can use `dod` (date of death) and `intime` to compute age? But we don't have birth date. The `patients` table has `anchor_age` and `anchor_year`, but that is the age at the time of the first event. We can use that as a proxy? Or we can use the `admissions` table to get the admission time and then compute age from `anchor_year` and `admittime`? 

        - We can compute age at admission: 
            age = TIMESTAMP_DIFF(admittime, FROM_UNIXTIME(UNIX_SECONDS(CAST(CONCAT(anchor_year, '-01-01') AS TIMESTAMP))), YEAR) 
          but this is approximate. Alternatively, we can use `anchor_age` as the age at the time of the first event, which might be close to the ICU admission time? But it's not exact. 

        - Since the question specifies age 90-100, and we are dealing with elderly, we can use `anchor_age` and assume it's the age at the time of the event. But note: `anchor_age` is the age at the time of the first event in the database, which might be years before the ICU admission. This is a limitation. 

        - Alternatively, we can use the `admissions` table and `patients` table to compute age at admission: 
            age = TIMESTAMP_DIFF(admittime, FROM_UNIXTIME(UNIX_SECONDS(CAST(CONCAT(anchor_year, '-01-01') AS TIMESTAMP))), YEAR) 
          but this is not accurate because we don't have the exact birth date. 

        - The `patients` table has `anchor_year` and `anchor_year_group`, but no birth date. We can use `anchor_year` as the birth year? Then age at admission = YEAR(admittime) - anchor_year. But this is approximate. 

        - Given the constraints, we'll use `anchor_year` and compute age at admission as: 
            EXTRACT(YEAR FROM admittime) - anchor_year
          and then filter for age between 90 and 100.

        - But note: the patient might have been admitted in the same year as their birthday, so we might be off by one. We can use:
            TIMESTAMP_DIFF(admittime, DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL 1 YEAR), YEAR) 
          but that's complex. Alternatively, we can use the `dod` to compute age at death? But we don't have birth date. 

        - Since the question is about age 90-100, and we are using `anchor_year` as the birth year, we'll do:
            age = EXTRACT(YEAR FROM admittime) - anchor_year
          and then filter age between 90 and 100.

        - However, this might misclassify patients who had their birthday during the year. But for a 95-year-old, it's less critical. We'll proceed with this.

      - For sepsis: we are using ICD-10 codes from `diagnoses_icd`. We need to ensure that the diagnosis is associated with the ICU admission. We can join `diagnoses_icd` to `icustays` on `subject_id` and `hadm_id`. But note: one admission might have multiple diagnoses. We only need one sepsis diagnosis to include the admission.

      - For the first 24 hours: we must use `charttime` for labevents and microbiologyevents, and compare to `intime` of the ICU stay. We must ensure that the event is within the same ICU stay and admission.

      - For mortality: we use `hospital_expire_flag` from `admissions` for the admission. We join `icustays` to `admissions` on `hadm_id` and `subject_id`.

      - For LOS: we use `los` from `icustays` (ICU length of stay in hours).

  5. Tables to use:
      - `icustays` (for ICU stays, intime, outtime, los, hadm_id, subject_id)
      - `admissions` (for hospital admission details, including hospital_expire_flag, admittime)
      - `patients` (for gender, anchor_year, and to compute age)
      - `diagnoses_icd` (for sepsis diagnosis, icd_code, icd_version)
      - `labevents` (for lab tests)
      - `microbiologyevents` (for microbiology tests)

  6. Steps in the query:
      a. Create a CTE for the cohort: ICU stays for male patients aged 90-100 with sepsis.
          - Join `icustays` with `admissions` on `hadm_id` and `subject_id` to get admission details.
          - Join with `patients` on `subject_id` to get gender and anchor_year.
          - Compute age at admission: EXTRACT(YEAR FROM admittime) - anchor_year, and filter age between 90 and 100, and gender='M'.
          - Join with `diagnoses_icd` on `subject_id` and `hadm_id` and filter for icd_version=10 and icd_code in the sepsis list.

      b. For each ICU stay in the cohort, count the number of labevents and microbiologyevents in the first 24 hours.
          - For labevents: count where `charttime` between `intime` and `intime + INTERVAL 24 HOUR` and `hadm_id` matches.
          - Similarly for microbiologyevents.

      c. Compute diagnostic_utilization = lab_count + micro_count.

      d. Then, for the cohort, compute:
          - SD of diagnostic_utilization: STDDEV_POP(diagnostic_utilization)
          - p75 and p95: APPROX_QUANTILES(diagnostic_utilization, 100) OVER() but we can use APPROX_QUANTILES in a single row? Alternatively, we can use PERCENTILE_CONT or PERCENTILE_DISC. But BigQuery has APPROX_QUANTILES which returns an array. We can use:
                APPROX_QUANTILES(diagnostic_utilization, 100) 
            and then extract the 75th and 95th percentiles.

          - in-hospital mortality %: AVG(hospital_expire_flag) * 100
          - average LOS: AVG(los) / 24.0  (to get days)

      e. For "admissions versus overall ICU":
          - We need two counts:
              - Count of ICU stays in the cohort (sepsis, age 90-100, male)
              - Count of all ICU stays for age 90-100, male (regardless of sepsis)

          - We can compute this in a separate CTE or in the main query.

  7. We'll structure the query with multiple CTEs for clarity.

  8. Note: We must be cautious of duplicate counts? For example, one lab test might be counted multiple times? But each row in `labevents` is a distinct event, so counting rows is fine.

  9. We'll use the following sepsis ICD-10 codes (abbreviated for brevity, but we'll list the main ones). We'll use a list of codes that are commonly associated with sepsis.

      Sepsis ICD-10 codes (from above list, we can use a subset for simplicity, but we should include the main ones):
        'A40', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.4', 'A40.5', 'A40.6', 'A40.7', 'A40.8', 'A40.9',
        'A41', 'A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.6', 'A41.7', 'A41.8', 'A41.9',
        'R65.20', 'R65.21', 'R65.22', 'R65.23', 'R65.24', 'R65.25', 'R65.26', 'R65.27', 'R65.28', 'R65.29',
        'R65.30', 'R65.31', 'R65.32', 'R65.33', 'R65.34', 'R65.35', 'R65.36', 'R65.37', 'R65.38', 'R65.39'

      But note: the `diagnoses_icd` table has `icd_code` as a string, so we can use a list.

  10. We'll create a CTE for the cohort of ICU stays with sepsis.

  11. We'll create a CTE for the denominator (all ICU stays for age 90-100, male) for the "admissions versus overall ICU" metric.

  12. We'll compute the counts for the numerator and denominator separately.

  13. Finally, we'll output the metrics in one row.

  14. We must be cautious of performance: we are scanning large tables. We'll use filters early.

  15. We'll use the following schema: `physionet-data.mimiciv_3_1_hosp` for admissions, diagnoses_icd, patients; `physionet-data.mimiciv_3_1_icu` for icustays, labevents, microbiologyevents.

  16. We'll use the `icustays` table to get the ICU stays.

  17. For the first 24 hours, we must ensure that the labevents and microbiologyevents are within the ICU stay and within the first 24 hours. We can join on `hadm_id` and `subject_id` and filter by time.

  18. We'll use LEFT JOINs for labevents and microbiologyevents to include stays with zero tests.

  19. We'll use GROUP BY for each ICU stay to compute the counts.

  20. We'll then aggregate over the cohort.

  21. For the "admissions versus overall ICU", we can compute the ratio in a separate CTE and then join to the main metrics.

  22. We'll output one row with the following columns:
        sd_diagnostic_utilization, p75_diagnostic_utilization, p95_diagnostic_utilization, 
        in_hospital_mortality_percent, avg_los_days, admissions_vs_overall_icu_ratio

  23. We'll use the following for percentiles: 
        APPROX_QUANTILES(diagnostic_utilization, 100) 
      and then extract the 75th and 95th percentiles. But note: APPROX_QUANTILES returns an array of 101 elements (for 100 buckets). The 75th percentile is at index 75, and 95th at index 95.

  24. Alternatively, we can use PERCENTILE_CONT for exact percentiles, but that might be expensive. We'll use APPROX_QUANTILES for efficiency.

  25. We'll use the following for the ratio: 
        (SELECT COUNT(*) FROM cohort) / (SELECT COUNT(*) FROM all_icu_stays)

  26. We'll create CTEs for:
        - patients_with_age: to compute age at admission for males aged 90-100.
        - icu_stays_with_age: join icustays with admissions and patients_with_age.
        - sepsis_diagnoses: diagnoses_icd for sepsis ICD-10 codes.
        - cohort: icu_stays_with_age joined with sepsis_diagnoses on subject_id and hadm_id.
        - lab_counts: for each cohort ICU stay, count labevents in first 24h.
        - micro_counts: for each cohort ICU stay, count microbiologyevents in first 24h.
        - diagnostic_counts: combine lab and micro counts for each stay.
        - all_icu_stays: all ICU stays for males aged 90-100 (same age/gender filter as cohort, but without sepsis).

  27. Then, we'll compute the metrics from diagnostic_counts and cohort.

  28. We'll also compute the mortality and LOS from the cohort.

  29. Finally, we'll compute the ratio.

  30. We'll use the following for the ratio: 
        (SELECT COUNT(DISTINCT stay_id) FROM cohort) / (SELECT COUNT(DISTINCT stay_id) FROM all_icu_stays)

  31. But note: the cohort might have duplicate stays? We are using distinct stay_id.

  32. We'll use the following for the main aggregation:

        SELECT
          STDDEV_POP(diagnostic_utilization) AS sd_diagnostic_utilization,
          APPROX_QUANTILES(diagnostic_utilization, 100)[OFFSET(75)] AS p75_diagnostic_utilization,
          APPROX_QUANTILES(diagnostic_utilization, 100)[OFFSET(95)] AS p95_diagnostic_utilization,
          AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
          AVG(los) / 24.0 AS avg_los_days,
          (SELECT COUNT(DISTINCT stay_id) FROM cohort) / (SELECT COUNT(DISTINCT stay_id) FROM all_icu_stays) AS admissions_vs_overall_icu_ratio
        FROM diagnostic_counts

  33. But note: the cohort CTE already has the ICU stays, and we are joining to get the counts. We must ensure that we have one row per stay in diagnostic_counts.

  34. We'll create the diagnostic_counts CTE with one row per stay.

  35. We'll also include the hospital_expire_flag and los in the cohort CTE so we can use them in the main query.

  36. We'll structure the query accordingly.

  37. We must be cautious of NULLs: if there are no lab or micro events, the count will be 0.

  38. We'll use COALESCE for counts to 0.

  39. We'll use the following for the time filter: 
        charttime BETWEEN intime AND intime + INTERVAL 24 HOUR

  40. We'll use the correct dataset names.

  41. We'll use the following for the sepsis ICD-10 codes list.

  42. We'll write the query step by step.

  43. Note: The `microbiologyevents` table has `charttime`, so we can use the same time filter.

  44. We'll use LEFT JOINs for labevents and microbiologyevents to include stays with no tests.

  45. We'll group by stay_id to get the counts.

  46. We'll use the following for the cohort CTE:

        WITH patients_with_age AS (
          SELECT
            subject_id,
            anchor_year,
            -- We'll compute age at admission later when we join with admissions
          FROM `physionet-data.mimiciv_3_1_hosp.patients`
          WHERE gender = 'M'
        ),
        icu_stays_with_age AS (
          SELECT
            i.stay_id,
            i.subject_id,
            i.hadm_id,
            i.intime,
            i.los,
            a.admittime,
            a.hospital_expire_flag,
            -- Compute age at admission: we assume anchor_year is birth year
            EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
          FROM `physionet-data.mimiciv_3_1_icu.icustays` i
          INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
            ON i.hadm_id = a.hadm_id AND i.subject_id = a.subject_id
          INNER JOIN patients_with_age p
            ON i.subject_id = p.subject_id
          WHERE EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 90 AND 100
        ),
        sepsis_diagnoses AS (
          SELECT DISTINCT subject_id, hadm_id
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
          WHERE icd_version = 10
            AND icd_code IN (
              'A40', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.4', 'A40.5', 'A40.6', 'A40.7', 'A40.8', 'A40.9',
              'A41', 'A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.6', 'A41.7', 'A41.8', 'A41.9',
              'R65.20', 'R65.21', 'R65.22', 'R65.23', 'R65.24', 'R65.25', 'R65.26', 'R65.27', 'R65.28', 'R65.29',
              'R65.30', 'R65.31', 'R65.32', 'R65.33', 'R65.34', 'R65.35', 'R65.36', 'R65.37', 'R65.38', 'R65.39'
            )
        ),
        cohort AS (
          SELECT
            i.stay_id,
            i.subject_id,
            i.hadm_id,
            i.intime,
            i.los,
            i.hospital_expire_flag,
            i.age_at_admission
          FROM icu_stays_with_age i
          INNER JOIN sepsis_diagnoses s
            ON i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id
        ),
        lab_counts AS (
          SELECT
            c.stay_id,
            COUNT(l.labevent_id) AS lab_count
          FROM cohort c
          LEFT JOIN `physionet-data.mimiciv_3_1_icu.labevents` l
            ON c.hadm_id = l.hadm_id AND c.subject_id = l.subject_id
            AND l.charttime BETWEEN c.intime AND c.intime + INTERVAL 24 HOUR
          GROUP BY c.stay_id
        ),
        micro_counts AS (
          SELECT
            c.stay_id,
            COUNT(m.microevent_id) AS micro_count
          FROM cohort c
          LEFT JOIN `physionet-data.mimiciv_3_1_icu.microbiologyevents` m
            ON c.hadm_id = m.hadm_id AND c.subject_id = m.subject_id
            AND m.charttime BETWEEN c.intime AND c.intime + INTERVAL 24 HOUR
          GROUP BY c.stay_id
        ),
        diagnostic_counts AS (
          SELECT
            c.stay_id,
            c.hospital_expire_flag,
            c.los,
            COALESCE(l.lab_count, 0) + COALESCE(m.micro_count, 0) AS diagnostic_utilization
          FROM cohort c
          LEFT JOIN lab_counts l ON c.stay_id = l.stay_id
          LEFT JOIN micro_counts m ON c.stay_id = m.stay_id
        ),
        all_icu_stays AS (
          SELECT
            i.stay_id
          FROM `physionet-data.mimiciv_3_1_icu.icustays` i
          INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
            ON i.hadm_id = a.hadm_id AND i.subject_id = a.subject_id
          INNER JOIN patients_with_age p
            ON i.subject_id = p.subject_id
          WHERE EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 90 AND 100
        )

        SELECT
          STDDEV_POP(diagnostic_utilization) AS sd_diagnostic_utilization,
          APPROX_QUANTILES(diagnostic_utilization, 100)[OFFSET(75)] AS p75_diagnostic_utilization,
          APPROX_QUANTILES(diagnostic_utilization, 100)[OFFSET(95)] AS p95_diagnostic_utilization,
          AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
          AVG(los) / 24.0 AS avg_los_days,
          (SELECT COUNT(DISTINCT stay_id) FROM cohort) / (SELECT COUNT(DISTINCT stay_id) FROM all_icu_stays) AS admissions_vs_overall_icu_ratio
        FROM diagnostic_counts

  47. We must ensure that the time filter for labevents and microbiologyevents uses the correct time. We are using `intime` from the ICU stay.

  48. We are using `BETWEEN` which is inclusive. This is correct.

  49. We are using `COALESCE` to handle NULL counts.

  50. We are using `APPROX_QUANTILES` for percentiles. Note: this is an approximation, but for large datasets it's acceptable.

  51. We are computing the ratio as a float.

  52. We are grouping by nothing in the final SELECT because we are aggregating over the entire cohort.

  53. We must be cautious of the performance: we are scanning large tables. We are filtering early in the CTEs.

  54. We'll run this in BigQuery.

  55. We'll output the query as requested.

  56. Note: The `microbiologyevents` table might not have `charttime` for all rows? But the schema says it has `charttime`. We'll assume it does.

  57. We'll use the correct dataset names as per the constraints;