SELECT
    MAX(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS max_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND dx.seq_num = 1
    AND LOWER(d_dx.long_title) LIKE '%upper gastrointestinal bleed%';