WITH AdmittedPatients AS (
    -- Select relevant admission and patient details, filter by gender and age, and calculate LOS
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age,
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F' -- Filter for female patients
        AND pat.anchor_age BETWEEN 70 AND 80 -- Filter for age 70-80
),
SurgicalAdmissions AS (
    -- Filter admissions to include only 'surgical inpatients' (those with at least one procedure)
    SELECT
        ap.hadm_id,
        ap.discharge_location,
        ap.hospital_expire_flag,
        ap.los_days
    FROM
        AdmittedPatients AS ap
    WHERE
        EXISTS (
            -- Check if there's any procedure recorded for this admission
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd AS picd
            WHERE picd.hadm_id = ap.hadm_id
            LIMIT 1
        )
),
CategorizedAdmissions AS (
    -- Assign a discharge category to each surgical admission
    SELECT
        hadm_id,
        los_days,
        CASE
            WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
            WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
            WHEN discharge_location IN (
                'SKILLED NURSING FACILITY',
                'REHABILITATION FACILITY',
                'LONG TERM CARE HOSPITAL',
                'ACUTE HOSPITAL',
                'PSYCH HOSPITAL',
                'OTHER FACILITY',
                'ICF',
                'DISCH-TRAN TO PSYCH HOSP'
            ) THEN 'Facility'
            ELSE 'Other/Unknown' -- For any other discharge locations not explicitly requested
        END AS discharge_category
    FROM
        SurgicalAdmissions
)
-- Final aggregation to calculate total admissions and proportions for each category
SELECT
    discharge_category,
    COUNT(hadm_id) AS total_admissions,
    COUNTIF(los_days >= 7) AS admissions_los_ge_7_days,
    ROUND(COUNTIF(los_days >= 7) * 100.0 / COUNT(hadm_id), 2) AS proportion_los_ge_7_percent,
    COUNTIF(los_days >= 14) AS admissions_los_ge_14_days,
    ROUND(COUNTIF(los_days >= 14) * 100.0 / COUNT(hadm_id), 2) AS proportion_los_ge_14_percent
FROM
    CategorizedAdmissions
WHERE
    discharge_category IN ('Home', 'Facility', 'In-hospital Death') -- Only include requested categories
GROUP BY
    discharge_category
ORDER BY
    discharge_category;