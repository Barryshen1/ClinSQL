WITH SurgicalAdmissions AS (
    -- Step 1: Identify all hospital admissions that have at least one procedure recorded.
    -- This defines the 'surgical inpatient' pool for our analysis.
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
),
PatientAdmissionData AS (
    -- Step 2: Combine patient demographics and admission details.
    -- Apply the specified age and gender filters, and restrict to surgical admissions.
    -- Calculate Length of Stay (LOS) and categorize discharge outcomes.
    SELECT
        adm.subject_id,
        adm.hadm_id,
        -- Calculate LOS in full days
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Categorize discharge outcomes based on hospital_expire_flag and discharge_location
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Mortality'
            WHEN LOWER(adm.discharge_location) LIKE '%home%' OR LOWER(adm.discharge_location) LIKE '%self care%' THEN 'Discharged Home'
            ELSE 'Discharged to Facility' -- Catches skilled nursing, rehab, hospice, etc.
        END AS discharge_group
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        SurgicalAdmissions sa
        ON adm.hadm_id = sa.hadm_id
    WHERE
        pat.gender = 'M' -- Filter for male patients
        AND pat.anchor_age BETWEEN 67 AND 77 -- Filter for age range 67-77
)
-- Step 3: Calculate the requested statistics for each discharge outcome group.
SELECT
    discharge_group,
    COUNT(hadm_id) AS total_patients_in_group,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(STDDEV(los_days), 2) AS stddev_los_days,
    -- Calculate the percentage of patients with LOS <= 7 days
    ROUND(COUNTIF(los_days <= 7) * 100.0 / COUNT(hadm_id), 2) AS percent_los_le_7_days
FROM
    PatientAdmissionData
GROUP BY
    discharge_group
ORDER BY
    discharge_group;