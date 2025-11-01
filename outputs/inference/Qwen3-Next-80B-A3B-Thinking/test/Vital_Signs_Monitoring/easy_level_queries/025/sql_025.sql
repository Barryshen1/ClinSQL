WITH mean_rr_per_stay AS (
    SELECT
        i.stay_id,
        AVG(c.valuenum) AS mean_rr
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` i
        ON c.stay_id = i.stay_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 39 AND 49
        AND c.itemid = 618
        AND c.valuenum IS NOT NULL
        AND c.charttime BETWEEN i.intime AND i.outtime
    GROUP BY
        i.stay_id
)
SELECT
    APPROX_QUANTILES(mean_rr, 100)[OFFSET(75)] AS percentile_75
FROM
    mean_rr_per_stay;