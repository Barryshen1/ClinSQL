WITH
  cohort_admissions AS (
    -- Step 1: Identify female patients aged 45-55 at admission with a multi-trauma diagnosis.
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag,
      -- Calculate Length of Stay in days
      DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      -- Calculate age at the time of admission
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
      ) BETWEEN 45 AND 55
      -- Filter for admissions that have a multi-trauma diagnosis code
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = adm.hadm_id
          -- T07: Unspecified multiple injuries (ICD-10)
          -- 9599: INJURY, OTHER AND UNSPECIFIED (ICD-9)
          AND dx.icd_code IN ('T07', '9599')
      )
  ),

  med_complexity AS (
    -- Step 2: Compute medication complexity as the number of unique medications in the first 7 days.
    SELECT
      c.hadm_id,
      COUNT(DISTINCT em.medication) AS medication_complexity_score
    FROM cohort_admissions AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS em
      ON c.hadm_id = em.hadm_id
      -- Filter for medication administrations within the first 7 days of admission
      AND em.charttime >= c.admittime
      AND em.charttime <= DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    GROUP BY
      c.hadm_id
  ),

  readmission_info AS (
    -- Step 3: Determine 30-day readmission status for each admission of the cohort patients.
    SELECT
      hadm_id,
      CASE
        WHEN next_admittime IS NOT NULL AND DATE_DIFF(next_admittime, dischtime, DAY) <= 30
          THEN 1
        ELSE 0
      END AS is_readmitted_30d
    FROM (
      SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        -- Get the admission time of the next hospital stay for the same patient
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        -- Optimization: only process admissions for patients in our cohort
        subject_id IN (SELECT DISTINCT subject_id FROM cohort_admissions)
    )
  ),

  final_data_with_tertiles AS (
    -- Step 4: Combine all metrics and stratify admissions into tertiles based on the complexity score.
    SELECT
      c.hadm_id,
      c.los,
      c.hospital_expire_flag,
      mc.medication_complexity_score,
      COALESCE(ri.is_readmitted_30d, 0) AS is_readmitted_30d,
      -- Use NTILE to create 3 groups (tertiles) based on the score
      NTILE(3) OVER (ORDER BY mc.medication_complexity_score) AS score_tertile
    FROM cohort_admissions AS c
    INNER JOIN med_complexity AS mc
      ON c.hadm_id = mc.hadm_id
    LEFT JOIN readmission_info AS ri
      ON c.hadm_id = ri.hadm_id
  )

-- Step 5: Aggregate the results by tertile and compute the final report metrics.
SELECT
  score_tertile,
  COUNT(hadm_id) AS admissions,
  ROUND(AVG(medication_complexity_score), 2) AS mean_score,
  MIN(medication_complexity_score) AS min_score,
  MAX(medication_complexity_score) AS max_score,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  ROUND(AVG(is_readmitted_30d) * 100, 2) AS readmission_30d_pct
FROM final_data_with_tertiles
GROUP BY
  score_tertile
ORDER BY
  score_tertile;