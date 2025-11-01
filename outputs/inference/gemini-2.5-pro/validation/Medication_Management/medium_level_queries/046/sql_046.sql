WITH cohort AS (
    -- Step 1: Identify the cohort of male patients aged 63-73 with T2DM and HF.
    SELECT
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        AND adm.dischtime IS NOT NULL -- Ensure admission has ended to calculate 'final 24h'
        AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 63 AND 73
        AND adm.hadm_id IN (
            SELECT
                hadm_id
            FROM
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            GROUP BY
                hadm_id
            HAVING
                -- Condition 1: Patient must have a T2DM diagnosis code (ICD-9 or ICD-10)
                COUNTIF(
                    (icd_version = 10 AND icd_code LIKE 'E11%') OR
                    (icd_version = 9 AND (icd_code LIKE '250__0' OR icd_code LIKE '250__2'))
                ) > 0
                -- Condition 2: Patient must also have a Heart Failure diagnosis code (ICD-9 or ICD-10)
                AND COUNTIF(
                    (icd_version = 10 AND icd_code LIKE 'I50%') OR
                    (icd_version = 9 AND icd_code LIKE '428%')
                ) > 0
        )
),

patient_level_meds AS (
    -- Step 2: For each patient in the cohort, flag if they received Insulin or Oral Agents
    -- in the first and final 24h of admission.
    SELECT
        cp.hadm_id,
        cp.med_class,
        LOGICAL_OR(cp.in_first_24h) AS received_in_first_24h,
        LOGICAL_OR(cp.in_final_24h) AS received_in_final_24h
    FROM (
        SELECT
            c.hadm_id,
            CASE
                WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
                WHEN
                    LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR
                    LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR
                    LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR
                    LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR
                    LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' OR
                    LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR
                    LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%repaglinide%' OR
                    LOWER(pr.drug) LIKE '%acarbose%'
                    THEN 'Oral Agent'
                ELSE NULL
            END AS med_class,
            -- Flag if prescription overlaps with the first 24h of admission
            (pr.starttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
                AND COALESCE(pr.stoptime, c.dischtime) >= c.admittime) AS in_first_24h,
            -- Flag if prescription overlaps with the final 24h of admission
            (pr.starttime <= c.dischtime
                AND COALESCE(pr.stoptime, c.dischtime) >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)) AS in_final_24h
        FROM
            cohort AS c
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
            ON c.hadm_id = pr.hadm_id
    ) AS cp -- classified_prescriptions
    WHERE
        cp.med_class IS NOT NULL
    GROUP BY
        cp.hadm_id,
        cp.med_class
),

cohort_size AS (
    -- Denominator: Total number of unique patients in the cohort
    SELECT CAST(COUNT(DISTINCT hadm_id) AS FLOAT64) AS total_patients FROM cohort
),

all_med_classes AS (
    -- Helper to ensure both medication classes are in the final output
    SELECT 'Insulin' AS med_class
    UNION ALL
    SELECT 'Oral Agent' AS med_class
),

final_counts AS (
    -- Numerators: Count patients for each medication class in each time window
    SELECT
        amc.med_class,
        COUNT(DISTINCT CASE WHEN plm.received_in_first_24h THEN plm.hadm_id END) AS count_first_24h,
        COUNT(DISTINCT CASE WHEN plm.received_in_final_24h THEN plm.hadm_id END) AS count_final_24h
    FROM
        all_med_classes AS amc
    LEFT JOIN
        patient_level_meds AS plm
        ON amc.med_class = plm.med_class
    GROUP BY
        amc.med_class
)

-- Step 3: Calculate prevalence and net change
SELECT
    fc.med_class,
    ROUND(SAFE_DIVIDE(fc.count_first_24h, cs.total_patients) * 100, 2) AS prevalence_first_24h_pct,
    ROUND(SAFE_DIVIDE(fc.count_final_24h, cs.total_patients) * 100, 2) AS prevalence_final_24h_pct,
    ROUND(
        (SAFE_DIVIDE(fc.count_final_24h, cs.total_patients) * 100) -
        (SAFE_DIVIDE(fc.count_first_24h, cs.total_patients) * 100),
        2
    ) AS net_change_pp
FROM
    final_counts AS fc,
    cohort_size AS cs
ORDER BY
    fc.med_class;