SELECT
    PERCENTILE_CONT(mean_dbp_per_stay_value, 0.75) OVER() - PERCENTILE_CONT(mean_dbp_per_stay_value, 0.25) OVER() AS iqr_of_mean_dbp
FROM
    (
        SELECT
            icu.stay_id,
            AVG(ce.valuenum) AS mean_dbp_per_stay_value
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            ON p.subject_id = adm.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.icustays` AS icu
            ON adm.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
            ON icu.stay_id = ce.stay_id
        WHERE
            p.gender = 'M'
            -- Calculate age at admission
            AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 49 AND 59
            AND icu.last_careunit = 'Stepdown' -- Target care unit: 'Stepdown' is the direct representation of intermediate care in MIMIC-IV
            AND ce.itemid IN (220059, 220180) -- itemids for Arterial Blood Pressure diastolic and Non Invasive Blood Pressure diastolic
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 0 -- Exclude erroneous zero values
            AND ce.valuenum < 300 -- Exclude unrealistically high values
        GROUP BY
            icu.stay_id
        HAVING
            COUNT(ce.valuenum) > 0 -- Ensure there's at least one valid DBP measurement for the stay
    ) AS MeanDBPPerStay
LIMIT 1;