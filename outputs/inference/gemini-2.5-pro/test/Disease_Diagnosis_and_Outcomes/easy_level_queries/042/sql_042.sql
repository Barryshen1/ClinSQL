SELECT
    AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS avg_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
WHERE
    -- 1. Filter for female patients
    pat.gender = 'F'
    -- 2. Filter for patients aged 78-88 at the time of admission
    AND (pat.anchor_age + DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)) BETWEEN 78 AND 88
    -- 3. Filter for the primary diagnosis
    AND dx.seq_num = 1
    -- 4. Filter for Ischemic Heart Disease / ACS diagnoses using both ICD-9 and ICD-10
    AND (
        (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN '410' AND '414')
        OR
        (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) BETWEEN 'I20' AND 'I25')
    );