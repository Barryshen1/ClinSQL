WITH initial_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    a.dischtime IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_year IS NOT NULL
    AND p.anchor_age IS NOT NULL
),
first_transfer AS (
  SELECT 
    hadm_id,
    careunit,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.transfers`
),
non_icu_cohort AS (
  SELECT 
    c.*,
    t.careunit
  FROM initial_cohort c
  INNER JOIN first_transfer t
    ON c.hadm_id = t.hadm_id AND t.rn = 1
  WHERE 
    NOT REGEXP_CONTAINS(t.careunit, r'ICU|CCU|MICU|SICU|NICU|PICU|CSRU')
),
discharge_groups AS (
  SELECT 
    hadm_id,
    los_days,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_group
  FROM (
    SELECT 
      hadm_id,
      hospital_expire_flag,
      discharge_location,
      DATE_DIFF(dischtime, admittime, DAY) AS los_days,
      age_at_admission
    FROM non_icu_cohort
    WHERE age_at_admission BETWEEN 44 AND 54
  )
),
percentiles AS (
  SELECT 
    discharge_group,
    quantiles[OFFSET(50)] AS p50,
    quantiles[OFFSET(75)] AS p75,
    quantiles[OFFSET(90)] AS p90,
    quantiles[OFFSET(95)] AS p95
  FROM (
    SELECT 
      discharge_group,
      APPROX_QUANTILES(los_days, 100) AS quantiles
    FROM discharge_groups
    GROUP BY discharge_group
  )
),
pct_rank_7d AS (
  SELECT 
    discharge_group,
    (COUNTIF(los_days <= 7) * 100.0) / COUNT(*) AS pct_rank_7d
  FROM discharge_groups
  GROUP BY discharge_group
)
SELECT 
  p.discharge_group,
  p.p50,
  p.p75,
  p.p90,
  p.p95,
  r.pct_rank_7d
FROM percentiles p
JOIN pct_rank_7d r ON p.discharge_group = r.discharge_group
WHERE p.discharge_group IN ('Home', 'Hospice', 'Death')
ORDER BY p.discharge_group;