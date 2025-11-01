SELECT
    MIN(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) AS min_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 88 AND 98
    AND adm.admission_location NOT IN (
        'TRANSFER FROM HOSPITAL',
        'TRANSFER FROM SKILLED NURSING FACILITY',
        'TRANSFER FROM OTHER HEALTHCARE FACILITY'
    )
    AND dx.seq_num = 1
    AND LOWER(d_dx.long_title) LIKE '%pneumonia%';