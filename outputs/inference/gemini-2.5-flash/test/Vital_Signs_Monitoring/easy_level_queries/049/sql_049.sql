WITH PatientICUStayMAP AS (
    SELECT
        icu.subject_id,
        icu.stay_id,
        -- Calculate the average MAP for this ICU stay within its first 24 hours
        AVG(ce.valuenum) AS first_24hr_mean_map
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 85 AND 95 -- Filter for males aged 85-95
        AND ce.itemid IN (220052, 220181, 224322) -- itemids for Mean Arterial Pressure (Arterial BP Mean, MAP Non-invasive, MAP Continuous)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 10 AND 200 -- Filter for physiologically plausible MAP values
        AND ce.charttime >= icu.intime
        AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR) -- Filter for the first 24 hours of ICU stay
    GROUP BY
        icu.subject_id,
        icu.stay_id
    HAVING
        COUNT(ce.valuenum) > 0 -- Ensure at least one valid MAP measurement was found for the average
)
SELECT
    STDDEV(first_24hr_mean_map) AS stddev_first_24hr_map
FROM
    PatientICUStayMAP;