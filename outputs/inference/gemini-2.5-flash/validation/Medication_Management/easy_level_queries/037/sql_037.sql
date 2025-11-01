SELECT
    PERCENTILE_CONT(DATE_DIFF(pres.stoptime, pres.starttime, DAY), 0.25) OVER() AS percentile_25_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pres.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pres.subject_id = adm.subject_id AND pres.hadm_id = adm.hadm_id
WHERE
    pat.gender = 'F'
    AND pat.anchor_age = 55
    AND adm.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY', 'DIRECT ADMIT') -- Filtering for inpatient admissions
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND DATE_DIFF(pres.stoptime, pres.starttime, DAY) >= 0 -- Ensure valid durations
    AND (
        LOWER(pres.drug) LIKE '%lisinopril%' OR
        LOWER(pres.drug) LIKE '%enalapril%' OR
        LOWER(pres.drug) LIKE '%ramipril%' OR
        LOWER(pres.drug) LIKE '%benazapril%' OR
        LOWER(pres.drug) LIKE '%captopril%' OR
        LOWER(pres.drug) LIKE '%fosinopril%' OR
        LOWER(pres.drug) LIKE '%moexipril%' OR
        LOWER(pres.drug) LIKE '%perindopril%' OR
        LOWER(pres.drug) LIKE '%quinapril%' OR
        LOWER(pres.drug) LIKE '%trandolapril%'
    );