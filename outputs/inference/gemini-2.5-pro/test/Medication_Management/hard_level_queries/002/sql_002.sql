WITH ami_admissions AS (
  -- Step 1: Identify the base cohort of male patients aged 67-77 with an AMI diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    -- Calculate age at admission and filter
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 67 AND 77
    -- Filter for admissions with an AMI diagnosis using specific ICD codes
    AND a.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code LIKE '410%') -- AMI for ICD-9
        OR (icd_version = 10 AND icd_code LIKE 'I21%') -- AMI for ICD-10
    )
),

med_complexity_score AS (
  -- Step 2: Calculate medication complexity score for each admission in the cohort
  -- Score is defined as the number of unique medications in the first 24 hours
  SELECT
    ami.subject_id,
    ami.hadm_id,
    ami.admittime,
    ami.dischtime,
    ami.hospital_expire_flag,
    COUNT(DISTINCT em.medication) AS medication_complexity_score
  FROM
    ami_admissions AS ami
  LEFT JOIN -- Use LEFT JOIN to include patients with 0 medications
    `physionet-data.mimiciv_3_1_hosp.emar` AS em
    ON ami.hadm_id = em.hadm_id
    AND em.charttime BETWEEN ami.admittime AND DATETIME_ADD(ami.admittime, INTERVAL 24 HOUR)
  GROUP BY
    ami.subject_id,
    ami.hadm_id,
    ami.admittime,
    ami.dischtime,
    ami.hospital_expire_flag
),

readmission_flag AS (
  -- Step 3: Pre-calculate 30-day readmission flag for all hospital admissions
  SELECT
    hadm_id,
    CASE
      WHEN DATETIME_DIFF(
          LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime),
          dischtime,
          DAY
      ) <= 30 THEN 1
      ELSE 0
    END AS readmitted_30_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

cohort_with_all_data AS (
  -- Step 4: Combine cohort data with scores, LOS, and readmission flags
  SELECT
    mcs.hadm_id,
    mcs.medication_complexity_score,
    -- Calculate length of stay in days
    DATETIME_DIFF(mcs.dischtime, mcs.admittime, DAY) as los_days,
    mcs.hospital_expire_flag,
    COALESCE(rf.readmitted_30_days, 0) AS readmitted_30_days
  FROM
    med_complexity_score AS mcs
  LEFT JOIN
    readmission_flag AS rf
    ON mcs.hadm_id = rf.hadm_id
),

cohort_tertiles AS (
  -- Step 5: Stratify the cohort into tertiles based on the medication complexity score
  SELECT
    *,
    NTILE(3) OVER (ORDER BY medication_complexity_score) AS score_tertile
  FROM
    cohort_with_all_data
)

-- Step 6: Final aggregation to report metrics per tertile
SELECT
  score_tertile,
  COUNT(hadm_id) AS admission_count,
  CONCAT(
    CAST(MIN(medication_complexity_score) AS STRING),
    ' - ',
    CAST(MAX(medication_complexity_score) AS STRING)
  ) AS score_range,
  ROUND(AVG(medication_complexity_score), 2) AS mean_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(readmitted_30_days) * 100, 2) AS readmission_30_day_pct
FROM
  cohort_tertiles
GROUP BY
  score_tertile
ORDER BY
  score_tertile;