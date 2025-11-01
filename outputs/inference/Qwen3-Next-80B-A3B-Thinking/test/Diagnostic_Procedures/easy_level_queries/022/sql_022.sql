WITH filtered_admissions AS (
  SELECT
    admissions.hadm_id,
    patients.anchor_age,
    patients.anchor_year,
    EXTRACT(YEAR FROM admissions.admittime) AS adm_year,
    patients.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
    ON patients.subject_id = admissions.subject_id
  WHERE patients.gender = 'M'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 82 AND 92
)
SELECT MIN(procedure_count) AS min_procedures
FROM (
  SELECT
    fa.hadm_id,
    COUNT(DISTINCT CASE 
      WHEN dip.long_title LIKE '%pacemaker%' 
        OR dip.long_title LIKE '%defibrillator%' 
        OR dip.long_title LIKE '%ICD%' 
      THEN pi.icd_code 
    END) AS procedure_count
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    ON fa.hadm_id = pi.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  GROUP BY fa.hadm_id
) AS counts;