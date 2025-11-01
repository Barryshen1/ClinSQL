SELECT
    count(DISTINCT adm.hadm_id) AS total_admissions
FROM
    physionet-data.mimiciv_3_1_hosp.patients AS pat
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions AS adm
    ON pat.subject_id = adm.subject_id
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
    ON adm.hadm_id = dx.hadm_id
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d_dx
    ON dx.icd_code = d_dx.icd_code
    AND dx.icd_version = d_dx.icd_version
WHERE
    -- Patient criteria
    pat.gender = 'M'
    AND adm.insurance = 'Medicare'
    AND (
        pat.anchor_age + DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 77 AND 87

    -- Admission criteria
    AND adm.admission_location = 'EMERGENCY ROOM'

    -- Diagnosis criteria: principal diagnosis of pneumonia
    AND dx.seq_num = 1
    AND LOWER(d_dx.long_title) LIKE '%pneumonia%';