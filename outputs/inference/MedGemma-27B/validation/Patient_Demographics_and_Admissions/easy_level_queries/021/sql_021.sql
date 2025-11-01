WITH first_pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    a.admittime = (
      SELECT
        MIN(a2.admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
      WHERE
        a2.subject_id = a.subject_id
    )
    AND di.long_title ILIKE '%pneumonia%' -- Use ILIKE for case-insensitive matching
    AND a.hospital_expire_flag = 0 -- Filter for first admission only
)
SELECT
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN subject_id ELSE NULL END) * 100.0 / COUNT(subject_id) AS mortality_percentage
FROM first_pneumonia_admissions;