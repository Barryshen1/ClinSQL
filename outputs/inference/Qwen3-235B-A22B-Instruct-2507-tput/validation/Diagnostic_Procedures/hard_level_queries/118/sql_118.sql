WITH patient_ami AS (
  SELECT DISTINCT a.hadm_id, p.subject_id, p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    AND d_diag.icd_code LIKE 'I21%'
    OR d_diag.icd_code LIKE 'I22%'
),
first_icu_stay AS (
  SELECT 
    i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patient_ami pa ON i.hadm_id = pa.hadm_id
),
procedures_72h AS (
  SELECT 
    fis.stay_id, fis.hadm_id,
    COUNT(pv.itemid) AS procedure_count
  FROM first_icu_stay fis
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pv 
    ON fis.stay_id = pv.stay_id 
    AND pv.starttime >= fis.intime 
    AND pv.starttime <= DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
  WHERE fis.rn = 1
  GROUP BY fis.stay_id, fis.hadm_id
),
quartiles AS (
  SELECT 
    hadm_id,
    procedure_count,
    NTILE(4) OVER (ORDER BY procedure_count) AS proc_quartile
  FROM procedures_72h
)
SELECT
  q.proc_quartile,
  COUNT(*) AS n,
  AVG(q.procedure_count) AS mean_procedure_count,
  AVG(DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS mean_hospital_los_days,
  AVG(a.hospital_expire_flag) AS in_hospital_mortality_rate
FROM quartiles q
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
GROUP BY q.proc_quartile
ORDER BY q.proc_quartile;