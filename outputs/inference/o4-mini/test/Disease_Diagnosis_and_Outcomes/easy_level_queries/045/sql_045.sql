SELECT
  STDDEV_POP(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS sd_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 77 AND 87
  AND EXISTS (
    -- heart failure diagnosis
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
    WHERE d.hadm_id = a.hadm_id
      AND LOWER(dicd.long_title) LIKE '%heart failure%'
  )
  AND EXISTS (
    -- COPD diagnosis
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
    WHERE d.hadm_id = a.hadm_id
      AND (
        LOWER(dicd.long_title) LIKE '%copd%'
        OR LOWER(dicd.long_title) LIKE '%obstructive pulmonary%'
      )
  );