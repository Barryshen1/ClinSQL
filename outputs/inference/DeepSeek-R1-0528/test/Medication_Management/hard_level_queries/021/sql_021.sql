WITH base_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 41 AND 51
),

neutropenia_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 51256 -- ANC absolute
    AND valuenum < 1500
),

temp_events AS (
  -- ICU temperature (Celsius and Fahrenheit)
  SELECT
    hadm_id,
    charttime,
    CASE
      WHEN itemid = 223761 THEN (valuenum - 32) * 5/9 -- Convert F to C
      ELSE valuenum
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid IN (220045, 223761, 223762) -- Temperature items
    AND valuenum IS NOT NULL

  UNION ALL

  -- HOSP temperature (Celsius from lab)
  SELECT
    hadm_id,
    charttime,
    valuenum AS temp_c
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid = 50825 -- Temperature Celsius
    AND valuenum IS NOT NULL
),

fever_adm AS (
  SELECT DISTINCT
    t.hadm_id
  FROM temp_events t
  INNER JOIN base_cohort bc
    ON t.hadm_id = bc.hadm_id
  WHERE
    t.temp_c >= 38.0
    AND t.charttime BETWEEN bc.admittime AND bc.dischtime
),

cohort_with_conditions AS (
  SELECT bc.*
  FROM base_cohort bc
  INNER JOIN neutropenia_adm n
    ON bc.hadm_id = n.hadm_id
  INNER JOIN fever_adm f
    ON bc.hadm_id = f.hadm_id
),

med_count AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count -- Unique medications
  FROM cohort_with_conditions c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),

cohort_with_meds AS (
  SELECT
    c.*,
    COALESCE(m.med_count, 0) AS med_count, -- Handle no medications
    NTILE(3) OVER (ORDER BY m.med_count) AS tertile -- Split into tertiles
  FROM cohort_with_conditions c
  LEFT JOIN med_count m
    ON c.hadm_id = m.hadm_id
),

all_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

cohort_with_readmission AS (
  SELECT
    cm.*,
    a.next_admittime,
    CASE
      WHEN cm.hospital_expire_flag = 0 -- Only for survivors
        AND a.next_admittime IS NOT NULL
        AND a.next_admittime <= DATE_ADD(cm.dischtime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS readmission_flag
  FROM cohort_with_meds cm
  LEFT JOIN all_admissions a
    ON cm.hadm_id = a.hadm_id
)

SELECT
  tertile,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmission_flag) * 100 AS readmission_pct
FROM cohort_with_readmission
GROUP BY tertile
ORDER BY tertile;