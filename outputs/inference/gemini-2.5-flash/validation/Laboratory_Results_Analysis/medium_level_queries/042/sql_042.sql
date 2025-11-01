WITH admissions_filtered_by_age_gender AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.hospital_expire_flag,
        CAST(EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age AS INT64) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND CAST(EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age AS INT64) BETWEEN 84 AND 94
),
chest_pain_admissions AS (
    -- Filter admissions based on the presence of chest pain diagnoses
    SELECT
        afag.subject_id,
        afag.hadm_id,
        afag.hospital_expire_flag
    FROM
        admissions_filtered_by_age_gender AS afag
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        WHERE afag.subject_id = di.subject_id
          AND afag.hadm_id = di.hadm_id
          AND (
                (di.icd_version = 9 AND di.icd_code LIKE '786.5%') -- ICD-9 for chest pain
                OR
                (di.icd_version = 10 AND di.icd_code LIKE 'R07%') -- ICD-10 for chest pain
          )
    )
),
troponin_t_measurements AS (
    -- Get all Troponin T measurements for the target population
    SELECT
        cpa.subject_id,
        cpa.hadm_id,
        cpa.hospital_expire_flag,
        le.charttime,
        le.valuenum
    FROM
        chest_pain_admissions AS cpa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cpa.subject_id = le.subject_id AND cpa.hadm_id = le.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
        ON le.itemid = li.itemid
    WHERE
        li.label LIKE '%Troponin T%' -- Identify Troponin T measurements
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0 -- Ensure valid numeric values
),
first_troponin_t AS (
    -- Rank and select the first Troponin T measurement for each admission
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        charttime,
        valuenum,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime) AS rn
    FROM
        troponin_t_measurements
),
classified_troponin AS (
    -- Classify the first Troponin T measurement into categories
    SELECT
        subject_id,
        hadm_id,
        hospital_expire_flag,
        CASE
            WHEN valuenum < 0.01 THEN 'Normal (<0.01)'
            WHEN valuenum >= 0.01 AND valuenum < 0.03 THEN 'Borderline (0.01-0.03)'
            WHEN valuenum >= 0.03 THEN 'Elevated (>=0.03)'
            ELSE 'Unknown' -- Should ideally not be reached with prior filtering
        END AS troponin_category
    FROM
        first_troponin_t
    WHERE
        rn = 1 -- Select only the first measurement
)
-- Final aggregation to calculate counts, percentages, and mortality
SELECT
    ct.troponin_category,
    COUNT(ct.hadm_id) AS total_admissions,
    ROUND(COUNT(ct.hadm_id) * 100.0 / SUM(COUNT(ct.hadm_id)) OVER (), 2) AS percentage_of_admissions,
    ROUND(SUM(CASE WHEN ct.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(ct.hadm_id), 2) AS in_hospital_mortality_percentage
FROM
    classified_troponin AS ct
GROUP BY
    ct.troponin_category
ORDER BY
    CASE ct.troponin_category
        WHEN 'Normal (<0.01)' THEN 1
        WHEN 'Borderline (0.01-0.03)' THEN 2
        WHEN 'Elevated (>=0.03)' THEN 3
        ELSE 4
    END
;