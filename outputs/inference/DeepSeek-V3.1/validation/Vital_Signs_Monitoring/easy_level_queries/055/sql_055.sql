WITH sbp_data AS (
    SELECT 
        ie.subject_id,
        ie.stay_id,
        ce.valuenum AS sbp_value
    FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86
        AND (ie.first_careunit = 'Step-Down' OR ie.first_careunit = 'IMC'
             OR ie.last_careunit = 'Step-Down' OR ie.last_careunit = 'IMC')
        AND ce.itemid IN (220179, 225309)  -- SBP itemids
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= ie.intime
        AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
)
SELECT 
    STDDEV(sbp_value) AS sd_sbp
FROM sbp_data;