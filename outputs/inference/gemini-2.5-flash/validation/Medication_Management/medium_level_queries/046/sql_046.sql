WITH CohortAdmissions AS (
    -- Defines the patient cohort (male, 63-73, T2DM, HF)
    -- This CTE identifies admissions that meet the demographic and diagnostic criteria.
    WITH BaseCohort AS (
        SELECT
            ad.subject_id,
            ad.hadm_id,
            ad.admittime,
            ad.dischtime,
            (p.anchor_age + (CAST(FORMAT_TIMESTAMP('%Y', ad.admittime) AS INT64) - p.anchor_year)) AS age_at_admission
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
            ON ad.subject_id = p.subject_id
        WHERE
            p.gender = 'M'
            AND (p.anchor_age + (CAST(FORMAT_TIMESTAMP('%Y', ad.admittime) AS INT64) - p.anchor_year)) BETWEEN 63 AND 73
            AND ad.dischtime IS NOT NULL -- Ensure only completed admissions are considered for 'final 24h'
    ),
    T2DM_Admissions AS (
        SELECT DISTINCT
            ca.subject_id,
            ca.hadm_id
        FROM
            BaseCohort AS ca
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            ON ca.subject_id = di.subject_id AND ca.hadm_id = di.hadm_id
        WHERE
            (
                di.icd_version = 9 AND di.icd_code IN (
                    '25000', '25002', '25010', '25012', '25020', '25022',
                    '25030', '25032', '25040', '25042', '25050', '25052',
                    '25060', '25062', '25070', '25072', '25080', '25082',
                    '25090', '25092'
                )
            )
            OR
            (
                di.icd_version = 10 AND di.icd_code LIKE 'E11%'
            )
    ),
    HF_Admissions AS (
        SELECT DISTINCT
            ca.subject_id,
            ca.hadm_id
        FROM
            BaseCohort AS ca
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            ON ca.subject_id = di.subject_id AND ca.hadm_id = di.hadm_id
        WHERE
            (di.icd_version = 9 AND di.icd_code LIKE '428%')
            OR
            (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime
    FROM
        BaseCohort AS bc
    INNER JOIN
        T2DM_Admissions AS t2dm
        ON bc.subject_id = t2dm.subject_id AND bc.hadm_id = t2dm.hadm_id
    INNER JOIN
        HF_Admissions AS hf
        ON bc.subject_id = hf.subject_id AND bc.hadm_id = hf.hadm_id
),
FilteredPrescriptions AS (
    -- Joins the cohort admissions with prescriptions, filtering for relevant medications.
    -- Calculates the start/end times for the first and final 24-hour windows.
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        p.starttime,
        DATETIME_ADD(ca.admittime, INTERVAL 24 HOUR) AS first_24h_end,
        DATETIME_SUB(ca.dischtime, INTERVAL 24 HOUR) AS final_24h_start_window_earliest_possible -- Renamed for clarity
    FROM
        CohortAdmissions AS ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
        ON ca.subject_id = p.subject_id AND ca.hadm_id = p.hadm_id
    WHERE
        -- Identify insulin or oral antidiabetic agents by drug name (case-insensitive)
        LOWER(p.drug) LIKE '%insulin%'
        OR LOWER(p.drug) LIKE '%metformin%'
        OR LOWER(p.drug) LIKE '%glyburide%'
        OR LOWER(p.drug) LIKE '%glipizide%'
        OR LOWER(p.drug) LIKE '%glimepiride%'
        OR LOWER(p.drug) LIKE '%sitagliptin%'
        OR LOWER(p.drug) LIKE '%saxagliptin%'
        OR LOWER(p.drug) LIKE '%linagliptin%'
        OR LOWER(p.drug) LIKE '%alogliptin%'
        OR LOWER(p.drug) LIKE '%pioglitazone%'
        OR LOWER(p.drug) LIKE '%rosiglitazone%'
        OR LOWER(p.drug) LIKE '%empagliflozin%'
        OR LOWER(p.drug) LIKE '%canagliflozin%'
        OR LOWER(p.drug) LIKE '%dapagliflozin%'
        OR LOWER(p.drug) LIKE '%repaglinide%'
        OR LOWER(p.drug) LIKE '%nateglinide%'
        OR LOWER(p.drug) LIKE '%acarbose%'
        OR LOWER(p.drug) LIKE '%miglitol%'
),
AdmissionMedicationFlags AS (
    -- Determines for each admission if relevant medications were given in the first 24h
    -- and/or final 24h.
    SELECT
        fp.subject_id,
        fp.hadm_id,
        MAX(CASE
                WHEN fp.starttime >= fp.admittime AND fp.starttime < fp.first_24h_end THEN 1
                ELSE 0
            END) AS has_med_first_24h,
        MAX(CASE
                WHEN fp.starttime >= GREATEST(fp.admittime, fp.final_24h_start_window_earliest_possible)
                AND fp.starttime <= fp.dischtime THEN 1
                ELSE 0
            END) AS has_med_final_24h
    FROM
        FilteredPrescriptions AS fp
    GROUP BY
        fp.subject_id,
        fp.hadm_id
)
-- Final aggregation to calculate prevalence and net change across the entire cohort.
SELECT
    CAST(COUNT(DISTINCT ca.hadm_id) AS NUMERIC) AS total_admissions_in_cohort,
    CAST(SUM(COALESCE(amf.has_med_first_24h, 0)) AS NUMERIC) AS admissions_with_med_first_24h,
    (SUM(COALESCE(amf.has_med_first_24h, 0)) * 100.0) / COUNT(DISTINCT ca.hadm_id) AS prevalence_first_24h_percent,
    CAST(SUM(COALESCE(amf.has_med_final_24h, 0)) AS NUMERIC) AS admissions_with_med_final_24h,
    (SUM(COALESCE(amf.has_med_final_24h, 0)) * 100.0) / COUNT(DISTINCT ca.hadm_id) AS prevalence_final_24h_percent,
    ((SUM(COALESCE(amf.has_med_final_24h, 0)) - SUM(COALESCE(amf.has_med_first_24h, 0))) * 100.0) / COUNT(DISTINCT ca.hadm_id) AS net_change_percentage_points
FROM
    CohortAdmissions AS ca
LEFT JOIN -- Use LEFT JOIN to include all cohort admissions, even if no relevant prescriptions were found for them
    AdmissionMedicationFlags AS amf
    ON ca.subject_id = amf.subject_id AND ca.hadm_id = amf.hadm_id;