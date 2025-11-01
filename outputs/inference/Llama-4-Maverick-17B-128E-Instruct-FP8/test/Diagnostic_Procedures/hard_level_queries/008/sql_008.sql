WITH ugib_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Gastrointestinal hemorrhage%' OR d.long_title LIKE '%Upper gastrointestinal bleed%'
),
filtered_patients AS (
  SELECT p.subject_id, p.gender, icu.hadm_id, icu.stay_id, 
         p.anchor_age AS age,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'M' AND icu.hadm_id IN (SELECT hadm_id FROM ugib_patients)
  AND p.anchor_age BETWEEN 48 AND 58
),
icustay_times AS (
  SELECT stay_id, MIN(intime) AS intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY stay_id
),
procedures AS (
  SELECT pe.stay_id, COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN icustay_times ist ON pe.stay_id = ist.stay_id
  WHERE pe.starttime <= TIMESTAMP_ADD(ist.intime, INTERVAL 24 HOUR)
  AND pe.stay_id IN (SELECT stay_id FROM filtered_patients)
  GROUP BY pe.stay_id
),
patient_data AS (
  SELECT fp.stay_id, fp.hadm_id, fp.age, fp.admittime, fp.dischtime, fp.hospital_expire_flag,
         COALESCE(p.proc_count, 0) AS proc_count,
         DATETIME_DIFF(fp.dischtime, fp.admittime, DAY) AS hospital_los
  FROM filtered_patients fp
  LEFT JOIN procedures p ON fp.stay_id = p.stay_id
),
quintiles AS (
  SELECT stay_id, proc_count,
         NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM patient_data
)
SELECT 
  q.quintile,
  AVG(q.proc_count) AS avg_procedures,
  AVG(pd.hospital_los) AS avg_hospital_los,
  AVG(CAST(pd.hospital_expire_flag AS INT64)) * 100 AS in_hospital_mortality_pct
FROM quintiles q
JOIN patient_data pd ON q.stay_id = pd.stay_id
GROUP BY q.quintile
ORDER BY q.quintile;