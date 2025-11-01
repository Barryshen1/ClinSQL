WITH septic_shock_cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        pat.anchor_age,
        pat.gender,
        (SELECT COUNT(DISTINCT icd_code) 
         FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
         WHERE diag.hadm_id = adm.hadm_id) AS num_diagnoses,
        -- Correct 90-day mortality: from admission to death (using datetime)
        CASE 
            WHEN pat.dod IS NOT NULL AND DATETIME(pat.dod) <= DATETIME_ADD(adm.admittime, INTERVAL 90 DAY) THEN 1
            ELSE 0 
        END AS mortality_90day,
        -- LOS in days
        DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 63 AND 73
        AND adm.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE (icd_code = 'R65.21' AND icd_version = 10) 
               OR (icd_code = '785.52' AND icd_version = 9)
        )
        -- Replace HAVING with WHERE after computing num_diagnoses
        AND (SELECT COUNT(DISTINCT icd_code) 
             FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
             WHERE diag.hadm_id = adm.hadm_id) > 15
),
general_population AS (
    SELECT 
        adm.hadm_id,
        pat.gender,
        pat.anchor_age,
        -- Complication indicator
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
                JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
                    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
                WHERE diag.hadm_id = adm.hadm_id
                AND (d.long_title LIKE '%acute kidney injury%' 
                     OR d.long_title LIKE '%respiratory failure%')
            ) THEN 1
            ELSE 0
        END AS has_complication,
        -- LOS for survivors only
        CASE WHEN adm.hospital_expire_flag = 0 THEN DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) ELSE NULL END AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
),
profile_68M_16 AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        pat.anchor_age,
        pat.gender,
        (SELECT COUNT(DISTINCT icd_code) 
         FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
         WHERE diag.hadm_id = adm.hadm_id) AS num_diagnoses,
        -- Complication indicator
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag2
                JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
                    ON diag2.icd_code = d.icd_code AND diag2.icd_version = d.icd_version
                WHERE diag2.hadm_id = adm.hadm_id
                AND (d.long_title LIKE '%acute kidney injury%' 
                     OR d.long_title LIKE '%respiratory failure%')
            ) THEN 1
            ELSE 0
        END AS has_complication,
        DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age = 68
        -- Replace HAVING with WHERE
        AND (SELECT COUNT(DISTINCT icd_code) 
             FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
             WHERE diag.hadm_id = adm.hadm_id) = 16
),
los_percentiles AS (
    SELECT 
        los_days,
        PERCENT_RANK() OVER (ORDER BY los_days) AS los_percentile
    FROM general_population
    WHERE los_days IS NOT NULL
),
complication_percentiles AS (
    SELECT 
        has_complication,
        PERCENT_RANK() OVER (ORDER BY has_complication) AS complication_percentile
    FROM general_population
)
-- For septic shock cohort: mean 90-day mortality
SELECT 
    'Septic shock cohort' AS group_name,
    COUNT(*) AS num_patients,
    AVG(mortality_90day) AS mean_90day_mortality,
    NULL AS mean_los_survivors,
    NULL AS complication_rate,
    NULL AS los_percentile,
    NULL AS complication_percentile
FROM septic_shock_cohort
UNION ALL
-- For general population: average LOS and complication rate
SELECT 
    'General population' AS group_name,
    COUNT(*) AS num_patients,
    NULL AS mean_90day_mortality,
    AVG(los_days) AS mean_los_survivors,
    AVG(has_complication) AS complication_rate,
    NULL AS los_percentile,
    NULL AS complication_percentile
FROM general_population
UNION ALL
-- For profile 68M with 16 diagnoses: average LOS and complication rate
SELECT 
    '68M with 16 diagnoses' AS group_name,
    COUNT(*) AS num_patients,
    NULL AS mean_90day_mortality,
    AVG(los_days) AS mean_los_survivors,
    AVG(has_complication) AS complication_rate,
    (SELECT AVG(los_percentile) FROM los_percentiles lp 
     WHERE lp.los_days = (SELECT AVG(los_days) FROM profile_68M_16)) AS los_percentile,
    (SELECT AVG(complication_percentile) FROM complication_percentiles cp 
     WHERE cp.has_complication = (SELECT AVG(has_complication) FROM profile_68M_16)) AS complication_percentile
FROM profile_68M_16;