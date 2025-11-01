SELECT
    -- Count of unique patients meeting all criteria
    COUNT(DISTINCT fc.subject_id) AS num_patients_meeting_criteria,
    -- Count of unique admissions meeting all criteria
    COUNT(DISTINCT fc.hadm_id) AS num_admissions_meeting_criteria,
    -- Mean of the initial Troponin I values
    AVG(fc.initial_troponin_i) AS mean_initial_troponin_i,
    -- Median of the initial Troponin I values (50th percentile) using APPROX_QUANTILES
    APPROX_QUANTILES(fc.initial_troponin_i, 100)[OFFSET(50)] AS median_initial_troponin_i,
    -- 1st Quartile of the initial Troponin I values (25th percentile) using APPROX_QUANTILES
    APPROX_QUANTILES(fc.initial_troponin_i, 100)[OFFSET(25)] AS q1_initial_troponin_i,
    -- 3rd Quartile of the initial Troponin I values (75th percentile) using APPROX_QUANTILES
    APPROX_QUANTILES(fc.initial_troponin_i, 100)[OFFSET(75)] AS q3_initial_troponin_i,
    -- Interquartile Range (IQR = Q3 - Q1)
    (APPROX_QUANTILES(fc.initial_troponin_i, 100)[OFFSET(75)] - APPROX_QUANTILES(fc.initial_troponin_i, 100)[OFFSET(25)]) AS iqr_initial_troponin_i
FROM
    (
        SELECT
            iti.subject_id,
            iti.hadm_id,
            iti.initial_troponin_i
        FROM
            (
                SELECT
                    le.subject_id,
                    le.hadm_id,
                    le.valuenum AS initial_troponin_i,
                    -- Rank Troponin I measurements by charttime for each admission
                    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
                FROM
                    `physionet-data.mimiciv_3_1_hosp`.labevents le
                INNER JOIN
                    (
                        SELECT DISTINCT
                            pc.subject_id,
                            pc.hadm_id,
                            pc.admittime
                        FROM
                            (
                                SELECT
                                    p.subject_id,
                                    ad.hadm_id,
                                    ad.admittime,
                                    p.gender,
                                    p.anchor_age
                                FROM
                                    `physionet-data.mimiciv_3_1_hosp`.patients p
                                INNER JOIN
                                    `physionet-data.mimiciv_3_1_hosp`.admissions ad
                                    ON p.subject_id = ad.subject_id
                                WHERE
                                    p.gender = 'F'
                                    AND p.anchor_age BETWEEN 84 AND 94
                            ) AS pc -- Patients in the target age/gender range
                        INNER JOIN
                            `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
                            ON pc.hadm_id = di.hadm_id
                        WHERE
                            -- Filter for Acute Coronary Syndrome (ACS) diagnoses
                            (
                                (di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '411.1%')) -- ICD-9-CM for AMI and Unstable Angina
                                OR
                                (di.icd_version = 10 AND (di.icd_code LIKE 'I20.0%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I24%')) -- ICD-10-CM for ACS
                            )
                    ) AS acs_admissions
                    ON le.subject_id = acs_admissions.subject_id
                    AND le.hadm_id = acs_admissions.hadm_id
                WHERE
                    le.itemid = 51003 -- Itemid for Troponin I (checked in d_labitems); assuming this itemid represents Troponin I as intended by the user.
                    AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
                    -- Consider only measurements within the first 24 hours of admission
                    AND le.charttime >= acs_admissions.admittime
                    AND le.charttime <= DATETIME_ADD(acs_admissions.admittime, INTERVAL 24 HOUR)
            ) AS iti
        WHERE
            iti.rn = 1 -- Select the first Troponin I measurement for each admission
            AND iti.initial_troponin_i > 0.04 -- Filter where initial Troponin I exceeds 99th percentile ULN (assuming 0.04 ng/mL as provided in original query)
    ) AS fc;