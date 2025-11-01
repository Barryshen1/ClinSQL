SELECT
    MAX(le.valuenum) AS max_first_24h_serum_creatinine
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia
    ON adm.hadm_id = dia.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON dia.icd_code = d_diag.icd_code AND dia.icd_version = d_diag.icd_version
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d_lab
    ON le.itemid = d_lab.itemid
WHERE
    pat.gender = 'M'
    AND pat.anchor_age = 66
    AND LOWER(d_diag.long_title) LIKE '%heart failure%' -- Filter for Heart Failure diagnoses
    AND LOWER(d_lab.label) LIKE '%creatinine%'
    AND LOWER(d_lab.fluid) LIKE '%serum%' -- Filter for serum creatinine
    AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
    AND le.charttime >= adm.admittime -- Lab taken at or after admission
    AND le.charttime <= DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR); -- Lab taken within first 24 hours of admission;