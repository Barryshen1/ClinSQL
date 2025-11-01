WITH base_population AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code = '4151')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
        )
    )
),
first_icu_stay AS (
  SELECT 
    bp.*,
    i.stay_id,
    i.intime,
    ROW_NUMBER() OVER (PARTITION BY bp.hadm_id ORDER BY i.intime) AS icu_stay_order
  FROM base_population bp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON bp.hadm_id = i.hadm_id
),
first_stay AS (
  SELECT *
  FROM first_icu_stay
  WHERE icu_stay_order = 1
),
procedure_counts AS (
  SELECT 
    fs.subject_id,
    fs.hadm_id,
    fs.admittime,
    fs.dischtime,
    fs.hospital_expire_flag,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM first_stay fs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON fs.stay_id = p.stay_id
    AND p.starttime >= fs.intime
    AND p.starttime < DATETIME_ADD(fs.intime, INTERVAL 72 HOUR)
  GROUP BY fs.subject_id, fs.hadm_id, fs.admittime, fs.dischtime, fs.hospital_expire_flag
),
quintile_data AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM procedure_counts
)
SELECT 
  quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_hospital_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_pct
FROM quintile_data
GROUP BY quintile
ORDER BY quintile;