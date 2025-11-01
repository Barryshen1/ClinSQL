WITH avg_rr_per_stay AS (
    -- Calculate the average respiratory rate (RR) in the first 48 hours of ICU stay
    SELECT
        ce.stay_id,
        AVG(ce.valuenum) AS avg_rr_48h
    FROM
        `physionet-data.mimiciv_3_1_icu`.chartevents ce
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays ic
        ON ce.stay_id = ic.stay_id
    WHERE
        ce.itemid = 220210 -- Itemid for Respiratory Rate
        AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND ce.valuenum > 0          -- Exclude non-physiological or erroneous zero values
        -- Filter for events within the first 48 hours of the ICU stay
        AND ce.charttime BETWEEN ic.intime AND DATETIME_ADD(ic.intime, INTERVAL 48 HOUR)
    GROUP BY
        ce.stay_id
),
stroke_status_per_hadm AS (
    -- Determine if a stroke diagnosis (ICD-9 or ICD-10) was present for each hospital admission
    SELECT
        dg.hadm_id,
        MAX(CASE
                -- ICD-9 codes for stroke (430-438)
                WHEN dg.icd_version = 9 AND SUBSTR(dg.icd_code, 1, 3) BETWEEN '430' AND '438' THEN 1
                -- ICD-10 codes for stroke (I60-I69)
                WHEN dg.icd_version = 10 AND SUBSTR(dg.icd_code, 1, 3) BETWEEN 'I60' AND 'I69' THEN 1
                ELSE 0
            END) AS has_stroke
    FROM
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dg
    GROUP BY
        dg.hadm_id
)
SELECT
    -- Categorize the average RR for display
    CASE
        WHEN arr.avg_rr_48h < 12 THEN '<12'
        WHEN arr.avg_rr_48h BETWEEN 12 AND 20 THEN '12-20'
        WHEN arr.avg_rr_48h BETWEEN 21 AND 29 THEN '21-29'
        WHEN arr.avg_rr_48h >= 30 THEN '>=30'
        ELSE 'Unknown/No RR Data' -- Handle cases where no RR data for 48h was found
    END AS rr_category,
    -- Label stroke status
    CASE
        WHEN ss.has_stroke = 1 THEN 'Yes'
        ELSE 'No'
    END AS stroke_present,
    COUNT(DISTINCT ic.stay_id) AS num_icu_stays -- Count distinct ICU stays in each category
FROM
    `physionet-data.mimiciv_3_1_icu`.icustays ic
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON ic.subject_id = p.subject_id
LEFT JOIN
    avg_rr_per_stay arr
    ON ic.stay_id = arr.stay_id
LEFT JOIN
    stroke_status_per_hadm ss
    ON ic.hadm_id = ss.hadm_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51 -- Filter for female patients aged 41-51
GROUP BY
    rr_category,
    stroke_present
ORDER BY
    rr_category,
    stroke_present;