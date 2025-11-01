WITH index_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      USING (subject_id)
    -- principal diagnosis is UTI
    JOIN (
      SELECT DISTINCT subject_id, hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        USING (icd_code, icd_version)
      WHERE d.seq_num = 1
        AND LOWER(dd.long_title) LIKE '%urinary tract infection%'
    ) AS ut_idx
      USING (subject_id, hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(a.insurance) LIKE '%medicare%'
    AND a.admission_location = 'SKILLED NURSING FACILITY'
),
next_adm AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM index_adm
),
flagged AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN next_admittime IS NOT NULL
       AND DATE_DIFF(next_admittime, dischtime, DAY) BETWEEN 1 AND 30
      THEN 1 ELSE 0
    END AS readmitted_30d
  FROM next_adm
)
SELECT
  -- 30-day readmission rate
  ROUND(100.0 * SUM(readmitted_30d) / COUNT(*), 2) AS readmission_rate_pct,
  -- median LOS for readmitted
  (
    SELECT
      APPROX_QUANTILES(los_days, 2)[OFFSET(1)]
    FROM flagged
    WHERE readmitted_30d = 1
  ) AS median_los_readmitted_days,
  -- median LOS for non-readmitted
  (
    SELECT
      APPROX_QUANTILES(los_days, 2)[OFFSET(1)]
    FROM flagged
    WHERE readmitted_30d = 0
  ) AS median_los_non_readmitted_days,
  -- percent of stays > 6 days
  ROUND(
    100.0 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS pct_stays_gt_6_days
FROM flagged;