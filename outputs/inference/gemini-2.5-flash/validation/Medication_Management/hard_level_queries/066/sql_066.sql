WITH admission_cohort AS (
    -- Step 1: Define the Cohort - Male inpatients aged 43-53 with a transplant diagnosis
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate Length of Stay in days. Will be NULL if dischtime is NULL (ongoing stay).
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
        -- Filter for transplant diagnosis based on common ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.hadm_id = a.hadm_id
                AND di.icd_version IN (9, 10) -- MIMIC-IV uses both ICD-9 and ICD-10
                AND (
                       di.icd_code LIKE 'V42%' OR -- ICD-9: Organ or tissue replaced by transplant
                       di.icd_code LIKE 'Z94%' OR -- ICD-10: Transplanted organ and tissue status
                       di.icd_code LIKE '996.8%' OR -- ICD-9: Complications of transplanted organ, NEC
                       di.icd_code LIKE 'T86%'    -- ICD-10: Failure and rejection of transplanted organs and tissues
                    )
        )
),
medication_counts AS (
    -- Step 2: Calculate Medication Complexity Score (Distinct medications in first 7 days)
    SELECT
        ac.subject_id,
        ac.hadm_id,
        COUNT(DISTINCT pr.drug) AS medication_complexity_score
    FROM
        admission_cohort ac
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON ac.subject_id = pr.subject_id AND ac.hadm_id = pr.hadm_id
    WHERE
        pr.starttime >= ac.admittime
        AND pr.starttime < DATETIME_ADD(ac.admittime, INTERVAL 7 DAY)
    GROUP BY
        ac.subject_id, ac.hadm_id
),
readmission_status AS (
    -- Step 3: Identify 30-day readmissions for each admission
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime, -- Include admittime for LEAD function
        ac.dischtime,
        -- Get the admittime of the next admission for the same patient
        LEAD(ac.admittime) OVER (PARTITION BY ac.subject_id ORDER BY ac.admittime) AS next_admittime,
        CASE
            -- Check if a next admission exists, if it's within 30 days of discharge, and not on the same day.
            WHEN LEAD(ac.admittime) OVER (PARTITION BY ac.subject_id ORDER BY ac.admittime) IS NOT NULL
                 AND DATETIME_DIFF(LEAD(ac.admittime) OVER (PARTITION BY ac.subject_id ORDER BY ac.admittime), ac.dischtime, DAY) <= 30
                 AND DATETIME_DIFF(LEAD(ac.admittime) OVER (PARTITION BY ac.subject_id ORDER BY ac.admittime), ac.dischtime, DAY) > 0 THEN 1
            ELSE 0
        END AS readmitted_30d
    FROM
        admission_cohort ac
),
patient_admission_data AS (
    -- Step 4: Combine all previous steps and assign quartiles per admission
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.los_days,
        ac.hospital_expire_flag,
        -- Assign 0 complexity if no prescriptions were found in the first 7 days
        COALESCE(mc.medication_complexity_score, 0) AS medication_complexity_score,
        rs.readmitted_30d,
        -- Assign quartiles based on medication complexity score
        NTILE(4) OVER (ORDER BY COALESCE(mc.medication_complexity_score, 0)) AS med_complexity_quartile
    FROM
        admission_cohort ac
    LEFT JOIN
        medication_counts mc
        ON ac.hadm_id = mc.hadm_id
    LEFT JOIN
        readmission_status rs
        ON ac.hadm_id = rs.hadm_id
    WHERE ac.dischtime IS NOT NULL -- Only consider completed hospital stays for LOS and readmission calculations
)
-- Step 5: Final Aggregation by Quartile
SELECT
    med_complexity_quartile,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    AVG(medication_complexity_score) AS mean_med_complexity_score,
    AVG(los_days) AS mean_los_days,
    AVG(hospital_expire_flag) AS mortality_rate, -- hospital_expire_flag is 0 or 1, so AVG gives the rate
    AVG(readmitted_30d) AS readmission_rate -- readmitted_30d is 0 or 1, so AVG gives the rate
FROM
    patient_admission_data
WHERE
    los_days IS NOT NULL -- This was redundant with ac.dischtime IS NOT NULL in the previous CTE, but kept for clarity.
GROUP BY
    med_complexity_quartile
ORDER BY
    med_complexity_quartile;