WITH AKI_Patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age >= 81
    AND p.anchor_age <= 91
    AND di.long_title LIKE '%acute kidney injury%'
    AND d.seq_num = 1 -- Assuming primary diagnosis is the first one listed
)
SELECT
  PERCENTILE_CONT(0.25, a.los) AS IQR_25th_percentile,
  PERCENTILE_CONT(0.75, a.los) AS IQR_75th_percentile
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
WHERE
  a.hadm_id IN (SELECT hadm_id FROM AKI_Patients);