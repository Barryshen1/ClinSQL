WITH hhs_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%hyperosmolar%' OR LOWER(d.long_title) LIKE '%hhs%'
),

admissions_hhs AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         p.gender,
         p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hhs_diagnoses h ON a.hadm_id = h.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 66 AND 76
),

icu_stays AS (
  SELECT i.stay_id, i.hadm_id, i.intime, i.los,
         a.hospital_expire_flag,
         a.hospital_los
  FROM admissions_hhs a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
),

procedure_counts AS (
  SELECT i.stay_id,
         COUNT(pe.itemid) AS procedure_count_48h
  FROM icu_stays i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL 48 HOUR
  GROUP BY i.stay_id
),

readmission_30d AS (
  SELECT a.hadm_id,
         MAX(CASE WHEN a2.admittime IS NOT NULL THEN 1 ELSE 0 END) AS readmission_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a.subject_id = a2.subject_id
    AND a2.admittime > a.dischtime
    AND a2.admittime <= a.dischtime + INTERVAL 30 DAY
  GROUP BY a.hadm_id
),

final_data AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.hospital_expire_flag,
    i.hospital_los,
    pc.procedure_count_48h,
    r.readmission_30d,
    NTILE(5) OVER (ORDER BY pc.procedure_count_48h) AS quintile
  FROM icu_stays i
  LEFT JOIN procedure_counts pc ON i.stay_id = pc.stay_id
  LEFT JOIN readmission_30d r ON i.hadm_id = r.hadm_id
)

SELECT
  quintile,
  COUNT(stay_id) AS num_icu_stays,
  AVG(procedure_count_48h) AS mean_procedures,
  MIN(procedure_count_48h) AS min_procedures,
  MAX(procedure_count_48h) AS max_procedures,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS hospital_mortality_pct,
  AVG(hospital_los) AS mean_hospital_los,
  AVG(CAST(readmission_30d AS FLOAT64)) * 100 AS readmission_30d_pct
FROM final_data
GROUP BY quintile
ORDER BY quintile;