SELECT
    COUNT(DISTINCT ga.hadm_id) AS total_cohort_admissions,
    SUM(ga.received_glp1_first_12h) AS admissions_first_12h_glp1_count,
    ROUND(SUM(ga.received_glp1_first_12h) * 100.0 / COUNT(DISTINCT ga.hadm_id), 2) AS percent_first_12h_glp1,
    SUM(ga.received_glp1_last_12h) AS admissions_last_12h_glp1_count,
    ROUND(SUM(ga.received_glp1_last_12h) * 100.0 / COUNT(DISTINCT ga.hadm_id), 2) AS percent_last_12h_glp1,
    ROUND((SUM(ga.received_glp1_last_12h) * 100.0 / COUNT(DISTINCT ga.hadm_id)) -
          (SUM(ga.received_glp1_first_12h) * 100.0 / COUNT(DISTINCT ga.hadm_id)), 2) AS net_change_percent
FROM
    ( -- CTE glp1_activity
        SELECT
            tc.hadm_id,
            tc.admittime,
            tc.dischtime,
            -- Check if GLP-1 RA was prescribed in the first 12 hours
            MAX(CASE WHEN gp.starttime BETWEEN tc.admittime AND TIMESTAMP_ADD(tc.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS received_glp1_first_12h,
            -- Check if GLP-1 RA was prescribed in the final 12 hours of admission
            MAX(CASE WHEN gp.starttime BETWEEN GREATEST(tc.admittime, TIMESTAMP_SUB(tc.dischtime, INTERVAL 12 HOUR)) AND tc.dischtime THEN 1 ELSE 0 END) AS received_glp1_last_12h
        FROM
            ( -- CTE target_cohort
                SELECT DISTINCT
                    ad.hadm_id,
                    ad.admittime,
                    ad.dischtime
                FROM
                    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
                INNER JOIN
                    `physionet-data.mimiciv_3_1_hosp.patients` AS pa
                    ON ad.subject_id = pa.subject_id
                WHERE
                    pa.gender = 'M'
                    AND pa.anchor_age BETWEEN 48 AND 58
                    AND ad.dischtime IS NOT NULL -- Exclude admissions without a defined discharge for 'final 12h'
                    -- Check for Type 2 Diabetes diagnosis
                    AND EXISTS (
                        SELECT 1
                        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_t2d
                        WHERE diag_t2d.hadm_id = ad.hadm_id
                        AND (
                            (diag_t2d.icd_version = 10 AND diag_t2d.icd_code LIKE 'E11%') -- ICD-10 Type 2 Diabetes
                            OR (diag_t2d.icd_version = 9 AND diag_t2d.icd_code LIKE '250%') -- ICD-9 Diabetes Mellitus (used to broadly capture Type 2)
                        )
                    )
                    -- Check for Heart Failure diagnosis
                    AND EXISTS (
                        SELECT 1
                        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag_hf
                        WHERE diag_hf.hadm_id = ad.hadm_id
                        AND (
                            (diag_hf.icd_version = 10 AND diag_hf.icd_code LIKE 'I50%') -- ICD-10 Heart Failure
                            OR (diag_hf.icd_version = 9 AND diag_hf.icd_code LIKE '428%') -- ICD-9 Heart Failure
                        )
                    )
            ) AS tc
        LEFT JOIN
            ( -- CTE glp1_prescriptions
                SELECT
                    p.hadm_id,
                    p.starttime
                FROM
                    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
                WHERE
                    LOWER(p.drug) LIKE '%exenatide%' OR
                    LOWER(p.drug) LIKE '%liraglutide%' OR
                    LOWER(p.drug) LIKE '%dulaglutide%' OR
                    LOWER(p.drug) LIKE '%semaglutide%' OR
                    LOWER(p.drug) LIKE '%lixisenatide%' OR
                    LOWER(p.drug) LIKE '%byetta%' OR
                    LOWER(p.drug) LIKE '%bydureon%' OR
                    LOWER(p.drug) LIKE '%victoza%' OR
                    LOWER(p.drug) LIKE '%saxenda%' OR
                    LOWER(p.drug) LIKE '%trulicity%' OR
                    LOWER(p.drug) LIKE '%ozempic%' OR
                    LOWER(p.drug) LIKE '%rybelsus%' OR
                    LOWER(p.drug) LIKE '%wegovy%' OR
                    LOWER(p.drug) LIKE '%adlyxin%'
            ) AS gp
            ON tc.hadm_id = gp.hadm_id
        GROUP BY
            tc.hadm_id, tc.admittime, tc.dischtime
    ) AS ga;