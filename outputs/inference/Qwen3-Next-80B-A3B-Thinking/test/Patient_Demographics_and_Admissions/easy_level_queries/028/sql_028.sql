SELECT STDDEV(los) AS std_dev_los
FROM (
    SELECT i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN (
        SELECT DISTINCT d.hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.patients` p
        JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
        WHERE p.gender = 'M'
          AND p.anchor_age BETWEEN 90 AND 100
          AND (LOWER(di.long_title) LIKE '%sepsis%' OR LOWER(di.long_title) LIKE '%septicemia%')
    ) s ON i.hadm_id = s.hadm_id
) AS subquery;