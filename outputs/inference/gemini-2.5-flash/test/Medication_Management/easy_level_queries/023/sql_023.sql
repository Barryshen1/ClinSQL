SELECT
    STDDEV(
        DATE_DIFF(
            LEAST(presc.stoptime, adm.dischtime), -- Effective end of inpatient prescription
            GREATEST(presc.starttime, adm.admittime), -- Effective start of inpatient prescription
            DAY
        )
    ) AS stddev_inpatient_acei_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
    ON adm.subject_id = presc.subject_id AND adm.hadm_id = presc.hadm_id
WHERE
    pat.gender = 'F' -- Filter for female patients
    -- Calculate age at admission and filter for 78-88 years old
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 78 AND 88
    -- Ensure necessary date/time fields are not null for duration calculation
    AND presc.starttime IS NOT NULL
    AND presc.stoptime IS NOT NULL
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    -- Filter for common ACE Inhibitors (case-insensitive)
    AND (
        LOWER(presc.drug) LIKE '%lisinopril%'
        OR LOWER(presc.drug) LIKE '%ramipril%'
        OR LOWER(presc.drug) LIKE '%enalapril%'
        OR LOWER(presc.drug) LIKE '%captopril%'
        OR LOWER(presc.drug) LIKE '%fosinopril%'
        OR LOWER(presc.drug) LIKE '%benazepril%'
        OR LOWER(presc.drug) LIKE '%moexipril%'
        OR LOWER(presc.drug) LIKE '%perindopril%'
        OR LOWER(presc.drug) LIKE '%quinapril%'
        OR LOWER(presc.drug) LIKE '%trandolapril%'
        -- Add any other relevant ACE inhibitors as needed
    )
    -- Ensure the calculated inpatient duration is greater than 0 days
    AND DATE_DIFF(
            LEAST(presc.stoptime, adm.dischtime),
            GREATEST(presc.starttime, adm.admittime),
            DAY
        ) > 0;