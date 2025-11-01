WITH
  -- CTE 1: Find all hospital admissions that match the cohort criteria (index admissions)
  cohort_admissions AS (
    SELECT
      ad.subject_id,
      ad.hadm_id,
      ad.admittime,
      ad.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pa ON ad.subject_id = pa.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON ad.hadm_id = dx.hadm_id
    WHERE
      -- Male patients
      pa.gender = 'M'
      -- Aged 68-78 at admission
      AND (
        DATETIME_DIFF(ad.admittime, DATETIME(pa.anchor_year, 1, 1, 0, 0, 0), YEAR) + pa.anchor_age
      ) BETWEEN 68 AND 78
      -- Medicare insurance
      AND ad.insurance = 'Medicare'
      -- Admitted from SNF
      AND (
        ad.admission_location LIKE '%SKILLED NURSING FACILITY%'
        OR ad.admission_location LIKE '%SNF%'
      )
      -- Principal diagnosis of UTI
      AND dx.seq_num = 1
      AND dx.icd_code IN (
        '5990',  -- ICD-9 for UTI, site not specified
        'N390'  -- ICD-10 for UTI, site not specified
      )
  ),
  -- CTE 2: For each patient in the cohort, find their next admission time
  next_admissions AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    WHERE
      subject_id IN (
        SELECT DISTINCT
          subject_id
        FROM
          cohort_admissions
      )
  ),
  -- CTE 3: Combine cohort info with readmission info and calculate metrics per stay
  analysis_base AS (
    SELECT
      c.hadm_id,
      -- Calculate index length of stay in days
      DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS index_los_days,
      -- Flag if the stay was > 6 days
      CASE
        WHEN DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 > 6
        THEN 1
        ELSE 0
      END AS is_los_gt_6,
      -- Flag if readmitted within 30 days of discharge
      CASE
        WHEN DATETIME_DIFF(na.next_admittime, c.dischtime, DAY) <= 30
        THEN 1
        ELSE 0
      END AS is_readmitted_30d
    FROM
      cohort_admissions AS c
      LEFT JOIN next_admissions AS na ON c.subject_id = na.subject_id AND c.hadm_id = na.hadm_id
  )
-- Final step: Aggregate the results to calculate the final metrics
SELECT
  -- Calculate 30-day readmission rate
  AVG(is_readmitted_30d) * 100 AS readmission_rate_30d,
  -- Calculate median LOS for readmitted vs non-readmitted patients
  APPROX_QUANTILES(
    CASE WHEN is_readmitted_30d = 1 THEN index_los_days END, 100
  )[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(
    CASE WHEN is_readmitted_30d = 0 THEN index_los_days END, 100
  )[OFFSET(50)] AS median_los_not_readmitted,
  -- Calculate the percentage of stays longer than 6 days
  AVG(is_los_gt_6) * 100 AS percent_stays_gt_6_days
FROM
  analysis_base;