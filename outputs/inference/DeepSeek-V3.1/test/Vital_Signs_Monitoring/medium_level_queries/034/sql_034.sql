WITH eligible_stays AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.intime,
        ie.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 37 AND 47
        AND ie.stay_id IN (
            SELECT DISTINCT stay_id
            FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
            WHERE itemid IN (227194, 227195)  -- CPAP and BiPAP
            AND starttime <= ie.outtime
            AND endtime >= ie.intime
        )
),
max_dbp_per_stay AS (
    SELECT 
        es.stay_id,
        MAX(ce.valuenum) AS max_dbp
    FROM eligible_stays es
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON es.stay_id = ce.stay_id
    WHERE 
        ce.itemid IN (220179, 220180)  -- Non-invasive and invasive diastolic BP
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
        AND ce.valuenum < 300
        AND ce.charttime BETWEEN es.intime AND es.outtime
    GROUP BY es.stay_id
)
SELECT 
    APPROX_QUANTILES(max_dbp, 100)[OFFSET(25)] AS percentile_25
FROM max_dbp_per_stay;