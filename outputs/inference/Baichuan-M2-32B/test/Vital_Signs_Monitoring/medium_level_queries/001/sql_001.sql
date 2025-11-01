WITH sbp_measurements AS (
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        ce.charttime,
        ce.valuenum AS sbp_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
        AND di.category = 'Vital Signs'
        AND di.label LIKE '%SBP%'  -- This might capture multiple, but we can refine if needed
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ce.subject_id = ie.subject_id
        AND ce.hadm_id = ie.hadm_id
        AND ce.stay_id = ie.stay_id
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    WHERE ce.valuenum IS NOT NULL
),
avg_sbp_per_stay AS (
    SELECT
        subject_id,
        stay_id,
        AVG(sbp_value) AS avg_sbp
    FROM sbp_measurements
    GROUP BY subject_id, stay_id
),
patient_demographics AS (
    SELECT
        subject_id,
        anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
        AND anchor_age BETWEEN 45 AND 55
),
filtered_stays AS (
    SELECT
        a.subject_id,
        a.stay_id,
        a.avg_sbp
    FROM avg_sbp_per_stay a
    INNER JOIN patient_demographics p
        ON a.subject_id = p.subject_id
),
categorized_sbp AS (
    SELECT
        subject_id,
        CASE
            WHEN avg_sbp < 140 THEN '<140'
            WHEN avg_sbp BETWEEN 140 AND 159 THEN '140-159'
            WHEN avg_sbp >= 160 THEN '>=160'
        END AS sbp_category
    FROM filtered_stays
)
SELECT
    sbp_category,
    COUNT(DISTINCT subject_id) AS num_patients
FROM categorized_sbp
GROUP BY sbp_category
ORDER BY sbp_category;