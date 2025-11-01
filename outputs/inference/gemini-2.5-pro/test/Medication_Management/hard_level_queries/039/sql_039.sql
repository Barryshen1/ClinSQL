WITH
  cohort AS (
    -- Step 1: Identify the base cohort of female patients aged 87-97 with an ICH diagnosis
    SELECT DISTINCT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    WHERE
      p.gender = 'F'
      AND ((EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 87 AND 97
      AND (
        d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('430', '431', '432')
        OR d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 3) IN ('I60', 'I61', 'I62')
      )
  ),

  medication_complexity AS (
    -- Step 2: Calculate medication complexity score for each admission in the cohort
    SELECT
      c.hadm_id,
      -- FIX: Concatenate fields to count distinct combinations, as COUNT(DISTINCT struct) is not allowed.
      COUNT(DISTINCT CONCAT(pres.drug, '|', pres.route)) AS complexity_score
    FROM
      cohort AS c
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
      ON c.hadm_id = pres.hadm_id
    WHERE
      -- Only include prescriptions within the first 48 hours of admission
      pres.starttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    GROUP BY
      c.hadm_id
  ),

  readmission_info AS (
    -- Step 3: Determine 30-day readmission status for cohort admissions
    SELECT
      hadm_id,
      CASE
        WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
        ELSE 0
      END AS readmitted_30_days
    FROM
      (
        SELECT
          a.subject_id,
          a.hadm_id,
          a.dischtime,
          -- Find the admission time of the next hospital stay for the same patient
          LEAD(a.admittime, 1) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions` a
        -- OPTIMIZATION: Only process admissions for patients in our specific cohort
        WHERE a.subject_id IN (SELECT subject_id FROM cohort)
      )
  ),

  admission_stats AS (
    -- Step 4: Combine cohort data with calculated metrics (LOS, complexity, readmission)
    SELECT
      c.hadm_id,
      DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
      c.hospital_expire_flag,
      COALESCE(mc.complexity_score, 0) AS complexity_score,
      COALESCE(ri.readmitted_30_days, 0) AS readmitted_30_days
    FROM
      cohort AS c
    LEFT JOIN
      medication_complexity AS mc
      ON c.hadm_id = mc.hadm_id
    LEFT JOIN
      readmission_info AS ri
      ON c.hadm_id = ri.hadm_id
  ),

  admission_quartiles AS (
    -- Step 5: Stratify admissions into quartiles based on the complexity score
    SELECT
      hadm_id,
      los_days,
      hospital_expire_flag,
      complexity_score,
      readmitted_30_days,
      NTILE(4) OVER (ORDER BY complexity_score) AS complexity_quartile
    FROM
      admission_stats
  )

-- Final Step: Aggregate results by quartile and report the final metrics
SELECT
  complexity_quartile,
  COUNT(hadm_id) AS number_of_admissions,
  CONCAT(
    CAST(MIN(complexity_score) AS STRING), ' - ', CAST(MAX(complexity_score) AS STRING)
  ) AS complexity_score_range,
  ROUND(AVG(los_days), 2) AS average_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percentage,
  ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_30_day_percentage
FROM
  admission_quartiles
GROUP BY
  complexity_quartile
ORDER BY
  complexity_quartile;