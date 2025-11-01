WITH hfnc_stays AS (
    SELECT DISTINCT ie.stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 81 AND 91
        AND ce.itemid = 226732
        AND ce.value = 'High Flow Nasal Cannula'
        AND ce.charttime BETWEEN ie.intime AND ie.outtime
)
SELECT MIN(mean_sbp) AS min_mean_sbp
FROM (
    SELECT ce.stay_id, AVG(ce.valuenum) AS mean_sbp
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN hfnc_stays hs
        ON ce.stay_id = hs.stay_id
    WHERE ce.itemid IN (220179, 220050)
        AND ce.valuenum IS NOT NULL
    GROUP BY ce.stay_id
) sbp_means;