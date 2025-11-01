SELECT STDDEV(los_days) AS sd_los
FROM (
    SELECT 
        a.hadm_id,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 77 AND 87
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
          WHERE d.hadm_id = a.hadm_id
            AND (di.long_title LIKE '%heart failure%' OR di.long_title LIKE '%congestive heart failure%')
      )
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
          WHERE d.hadm_id = a.hadm_id
            AND (di.long_title LIKE '%COPD%' OR di.long_title LIKE '%chronic obstructive pulmonary disease%')
      )
) AS los_data;