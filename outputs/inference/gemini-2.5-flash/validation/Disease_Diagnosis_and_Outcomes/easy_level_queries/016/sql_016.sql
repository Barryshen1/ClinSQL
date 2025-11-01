SELECT
    PERCENTILE_CONT(cohort_los.hospital_los_days, 0.75) OVER() AS p75_hospital_los_days
FROM (
    SELECT
        -- Ensure unique admissions for LOS calculation if there were any weird duplicates (though hadm_id is primary-like)
        -- The DISTINCT is generally good practice here before an aggregate if the inner query could produce duplicates for hadm_id,los
        af.hadm_id,
        af.hospital_los_days
    FROM (
        SELECT
            a.subject_id,
            a.hadm_id,
            a.admittime,
            a.dischtime,
            p.gender,
            -- Calculate age at admission
            CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) AS age_at_admission,
            DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los_days
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
            ON a.subject_id = p.subject_id
        WHERE
            p.gender = 'M'
            AND a.dischtime IS NOT NULL -- Ensure a valid discharge time for LOS calculation
    ) AS af
    WHERE
        -- Filter by age range 68-78 at admission
        af.age_at_admission BETWEEN 68 AND 78

        -- Check for presence of Pneumonia diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_pneumo
            WHERE
                di_pneumo.subject_id = af.subject_id
                AND di_pneumo.hadm_id = af.hadm_id
                AND (
                    (di_pneumo.icd_version = 10 AND (di_pneumo.icd_code LIKE 'J12%' OR di_pneumo.icd_code LIKE 'J13%' OR di_pneumo.icd_code LIKE 'J14%' OR di_pneumo.icd_code LIKE 'J15%' OR di_pneumo.icd_code LIKE 'J16%' OR di_pneumo.icd_code LIKE 'J17%' OR di_pneumo.icd_code LIKE 'J18%'))
                    OR
                    (di_pneumo.icd_version = 9 AND (di_pneumo.icd_code LIKE '480%' OR di_pneumo.icd_code LIKE '481%' OR di_pneumo.icd_code LIKE '482%' OR di_pneumo.icd_code LIKE '483%' OR di_pneumo.icd_code LIKE '484%' OR di_pneumo.icd_code LIKE '485%' OR di_pneumo.icd_code LIKE '486%'))
                )
        )
        -- Check for presence of COPD diagnosis
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di_copd
            WHERE
                di_copd.subject_id = af.subject_id
                AND di_copd.hadm_id = af.hadm_id
                AND (
                    (di_copd.icd_version = 10 AND di_copd.icd_code LIKE 'J44%')
                    OR
                    (di_copd.icd_version = 9 AND (di_copd.icd_code LIKE '491%' OR di_copd.icd_code LIKE '492%' OR di_copd.icd_code LIKE '496%'))
                )
        )
) AS cohort_los;