WITH
  -- Step 1: Identify hospital admissions associated with a 'hepatic failure' diagnosis.
  hepatic_failure_adms AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
      LOWER(d_dx.long_title) LIKE '%hepatic failure%'
  ),

  -- Step 2: For each admission, determine if a readmission occurred within 30 days of discharge.
  readmission_flags AS (
    SELECT
      hadm_id,
      CASE
        WHEN
          DATETIME_DIFF(
            LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime), dischtime, DAY
          ) <= 30
          THEN 1
        ELSE 0
      END AS readmission_30_day_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
  ),

  -- Step 3: Define the final patient cohort and calculate baseline outcomes.
  -- The cohort includes male patients aged 43-53 with hepatic failure.
  cohort_with_outcomes AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.hospital_expire_flag,
      COALESCE(rf.readmission_30_day_flag, 0) AS readmission_30_day_flag,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
    INNER JOIN
      hepatic_failure_adms AS hf ON adm.hadm_id = hf.hadm_id
    LEFT JOIN
      readmission_flags AS rf ON adm.hadm_id = rf.hadm_id
    WHERE
      pat.gender = 'M'
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) + pat.anchor_age BETWEEN 43 AND 53
  ),

  -- Step 4: Calculate the medication complexity score for each admission in the cohort.
  -- The score is the number of unique medications in the first 72 hours.
  cohort_with_scores AS (
    SELECT
      c.hadm_id,
      c.hospital_los,
      c.hospital_expire_flag,
      c.readmission_30_day_flag,
      COUNT(DISTINCT emar.medication) AS med_complexity_score
    FROM
      cohort_with_outcomes AS c
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.emar` AS emar
      ON c.hadm_id = emar.hadm_id
      AND emar.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    GROUP BY
      c.hadm_id,
      c.hospital_los,
      c.hospital_expire_flag,
      c.readmission_30_day_flag
  ),

  -- Step 5: Stratify the cohort into quintiles based on the medication complexity score.
  cohort_with_quintiles AS (
    SELECT
      *,
      NTILE(5) OVER (ORDER BY med_complexity_score) AS score_quintile
    FROM
      cohort_with_scores
  )

-- Final Step: Aggregate the metrics by quintile and present the results.
SELECT
  score_quintile,
  COUNT(hadm_id) AS n,
  MIN(med_complexity_score) AS min_score,
  MAX(med_complexity_score) AS max_score,
  ROUND(AVG(med_complexity_score), 2) AS mean_score,
  ROUND(AVG(hospital_los), 2) AS mean_los,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(CAST(readmission_30_day_flag AS FLOAT64)) * 100, 2) AS readmission_30_day_pct
FROM
  cohort_with_quintiles
GROUP BY
  score_quintile
ORDER BY
  score_quintile;