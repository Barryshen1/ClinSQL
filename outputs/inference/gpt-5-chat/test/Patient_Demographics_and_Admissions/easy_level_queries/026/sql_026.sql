WITH first_adm AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN (
    SELECT subject_id, hadm_id, admittime, hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) = 1
  ) a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
cabg_adm AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM first_adm fa
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON fa.subject_id = pr.subject_id
    AND fa.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%coronary artery bypass%'
)
SELECT
  PERCENTILE_CONT(hospital_expire_flag, 0.25) OVER() AS mortality_25th_percentile
FROM cabg_adm;