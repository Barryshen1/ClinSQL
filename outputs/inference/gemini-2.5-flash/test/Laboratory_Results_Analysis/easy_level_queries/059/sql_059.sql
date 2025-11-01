SELECT
    APPROX_QUANTILES(dp.platelet_count_valuenum, 100)[OFFSET(75)] AS p75_platelet_count
FROM
    (
        -- Step 2: Get all platelet counts on the discharge date for eligible admissions
        SELECT
            le.valuenum AS platelet_count_valuenum
        FROM
            `physionet-data.mimiciv_3_1_hosp.labevents` le
        INNER JOIN
            (
                -- Step 1: Identify eligible admissions (male, 93 years old, sepsis diagnosis)
                SELECT
                    ad.subject_id,
                    ad.hadm_id,
                    DATE(ad.dischtime) AS discharge_date
                FROM
                    `physionet-data.mimiciv_3_1_hosp.admissions` ad
                INNER JOIN
                    `physionet-data.mimiciv_3_1_hosp.patients` pa
                    ON ad.subject_id = pa.subject_id
                WHERE
                    pa.gender = 'M'
                    AND pa.anchor_age = 93
                    AND EXISTS (
                        SELECT 1
                        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                        WHERE
                            di.hadm_id = ad.hadm_id
                            AND (
                                (
                                    di.icd_version = 9 AND (
                                        di.icd_code LIKE '038%'
                                        OR di.icd_code IN ('99591', '99592')
                                    )
                                )
                                OR
                                (
                                    di.icd_version = 10 AND (
                                        di.icd_code LIKE 'A40%'
                                        OR di.icd_code LIKE 'A41%'
                                        OR di.icd_code LIKE 'R652%'
                                    )
                                )
                            )
                    )
            ) AS SepsisAdmissions
            ON le.subject_id = SepsisAdmissions.subject_id
            AND le.hadm_id = SepsisAdmissions.hadm_id
        WHERE
            le.itemid = 51265 -- Itemid for Platelet Count (verified from d_labitems)
            AND DATE(le.charttime) = SepsisAdmissions.discharge_date
            AND le.valuenum IS NOT NULL
            AND le.valuenum > 0 -- Ensure valid positive platelet count
    ) AS dp;