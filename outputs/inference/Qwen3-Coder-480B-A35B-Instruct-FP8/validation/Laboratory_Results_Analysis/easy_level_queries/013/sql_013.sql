SELECT MAX(max_creatinine) AS max_peak_creatinine
FROM (
    SELECT p.subject_id, MAX(le.valuenum) AS max_creatinine
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
        ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON a.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE p.gender = 'F'
      AND LOWER(did.long_title) LIKE '%chronic obstructive pulmonary disease%'
      AND LOWER(dli.label) LIKE '%creatinine%'
      AND le.valueuom = 'mg/dL'
      AND le.valuenum IS NOT NULL
      AND le.charttime BETWEEN a.admittime AND a.dischtime
    GROUP BY p.subject_id
);