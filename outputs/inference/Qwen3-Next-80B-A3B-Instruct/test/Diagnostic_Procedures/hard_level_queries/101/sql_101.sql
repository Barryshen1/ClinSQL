WITH copd_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures_72h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL '72' HOUR
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND LOWER(dicd.long_title) LIKE '%copd%'
    AND LOWER(dicd.long_title) LIKE '%exacerbation%'
  GROUP BY i.subject_id, i.stay_id, i.los, a.hospital_expire_flag
),
all_control_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    COUNT(DISTINCT pe.itemid) AS distinct_procedures_72h
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL '72' HOUR
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
  GROUP BY i.subject_id, i.stay_id, i.los, a.hospital_expire_flag
),
copd_summary AS (
  SELECT
    PERCENTILE_DISC(distinct_procedures_72h, 0.75) AS p75_procedures_copd,
    AVG(los) AS mean_los_copd,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_copd
  FROM copd_patients
),
control_summary AS (
  SELECT
    AVG(los) AS mean_los_control,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_control
  FROM all_control_patients
)
SELECT
  c.p75_procedures_copd,
  c.mean_los_copd,
  c.mortality_rate_copd,
  ctrl.mean_los_control,
  ctrl.mortality_rate_control
FROM copd_summary c
CROSS JOIN control_summary ctrl;