WITH PatientFirstAdmission AS (
    SELECT
        subject_id,
        MIN(admittime) AS first_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
)
-- Step 2: Select and count distinct admissions based on all specified criteria.
SELECT
    COUNT(DISTINCT a.hadm_id) AS number_of_index_admissions
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.hadm_id = di.hadm_id
JOIN
    PatientFirstAdmission AS pfa
    ON a.subject_id = pfa.subject_id
WHERE
    p.gender = 'F' -- Patient is female
    AND a.insurance = 'Medicare' -- Patient has Medicare insurance
    AND a.admission_location = 'EMERGENCY ROOM' -- Admission originated from the Emergency Department
    AND a.dischtime IS NOT NULL -- The admission has a documented discharge time, implying completion
    AND di.seq_num = 1 -- The diagnosis is the principal diagnosis for the admission
    AND (
        -- Calculate the patient's age at the time of THIS specific admission
        (p.anchor_age + DATE_DIFF(a.admittime, pfa.first_admittime, YEAR)) BETWEEN 68 AND 78
    )
    AND (
        -- Check for hemorrhagic stroke ICD-9 codes
        (di.icd_version = 9 AND di.icd_code IN ('430', '431', '432'))
        -- OR check for hemorrhagic stroke ICD-10 codes
        OR (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
    );