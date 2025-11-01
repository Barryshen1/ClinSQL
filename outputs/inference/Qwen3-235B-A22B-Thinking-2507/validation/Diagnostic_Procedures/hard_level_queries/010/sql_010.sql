WITH icu_stays_filtered AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    icu.los,
    adm.hospital_expire_flag,
    icu.intime,
    pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 40 AND 50
),
hemorrhagic_flag AS (
  SELECT 
    ist.stay_id,
    COALESCE(MAX(CASE 
      WHEN (d_icd.icd_version = 10 AND (d_icd.icd_code LIKE 'I60%' OR d_icd.icd_code LIKE 'I61%' OR d_icd.icd_code LIKE 'I62%')) 
        OR (d_icd.icd_version = 9 AND (d_icd.icd_code LIKE '430%' OR d_icd.icd_code LIKE '431%' OR d_icd.icd_code LIKE '432%')) 
      THEN 1 ELSE 0 
    END), 0) AS is_hemorrhagic
  FROM icu_stays_filtered ist
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON ist.hadm_id = d_icd.hadm_id
  GROUP BY ist.stay_id
),
procedure_counts AS (
  SELECT 
    ist.stay_id,
    COUNT(p_icd.seq_num) AS procedure_count
  FROM icu_stays_filtered ist
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
    ON ist.hadm_id = p_icd.hadm_id
    AND (
      (p_icd.icd_version = 10 AND p_icd.icd_code LIKE 'B%') 
      OR 
      (p_icd.icd_version = 9 AND (p_icd.icd_code LIKE '88%' OR p_icd.icd_code LIKE '89%'))
    )
    AND p_icd.chartdate <= DATE(TIMESTAMP_ADD(ist.intime, INTERVAL 72 HOUR))
  GROUP BY ist.stay_id
)
SELECT 
  hf.is_hemorrhagic,
  APPROX_QUANTILES(pc.procedure_count, 100)[OFFSET(90)] AS procedure_count_90th,
  APPROX_QUANTILES(ist.los, 100)[OFFSET(50)] AS los_median,
  AVG(ist.hospital_expire_flag) AS mortality_rate
FROM hemorrhagic_flag hf
INNER JOIN procedure_counts pc
  ON hf.stay_id = pc.stay_id
INNER JOIN icu_stays_filtered ist
  ON hf.stay_id = ist.stay_id
GROUP BY hf.is_hemorrhagic;