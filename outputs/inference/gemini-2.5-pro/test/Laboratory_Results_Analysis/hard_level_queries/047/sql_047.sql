WITH
-- Part 1: Define the ARDS Cohort
-- Identify ICU stays for male patients aged 71-81 with an ARDS diagnosis.
cohort AS (
    SELECT
        icu.stay_id,
        icu.hadm_id,
        icu.intime,
        DATETIME_ADD(icu.intime, INTERVAL 72 HOUR) AS endtime_72hr
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON icu.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'M'
        AND (DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age) BETWEEN 71 AND 81
        AND dx.icd_code IN ('J80', '51882') -- J80 is ICD-10 for ARDS, 51882 is ICD-9
    GROUP BY icu.stay_id, icu.hadm_id, icu.intime
),

-- Part 2: Calculate SOFA Score (as 'Instability Score') Components for the first 72 hours.
-- Respiration Score (PaO2/FiO2)
sofa_respiration AS (
    WITH pao2 AS (
        SELECT co.stay_id, le.charttime, le.valuenum
        FROM cohort co
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON co.hadm_id = le.hadm_id
        WHERE le.itemid = 50821 AND le.valuenum IS NOT NULL AND le.charttime BETWEEN co.intime AND co.endtime_72hr
    ),
    fio2 AS (
        SELECT co.stay_id, ce.charttime, CASE WHEN ce.valuenum > 1.0 THEN ce.valuenum / 100.0 ELSE ce.valuenum END AS valuenum
        FROM cohort co
        INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON co.stay_id = ce.stay_id
        WHERE ce.itemid = 223835 AND ce.valuenum IS NOT NULL AND ce.charttime BETWEEN co.intime AND co.endtime_72hr
    ),
    pao2fio2_paired AS (
        SELECT p.stay_id, p.valuenum / f.valuenum AS pao2fio2_ratio,
            ROW_NUMBER() OVER(PARTITION BY p.stay_id, p.charttime ORDER BY ABS(DATETIME_DIFF(p.charttime, f.charttime, SECOND))) AS rn
        FROM pao2 p
        LEFT JOIN fio2 f ON p.stay_id = f.stay_id AND f.charttime BETWEEN DATETIME_SUB(p.charttime, INTERVAL 2 HOUR) AND DATETIME_ADD(p.charttime, INTERVAL 2 HOUR)
        WHERE f.valuenum > 0
    )
    SELECT co.stay_id,
        CASE
            WHEN MIN(pf.pao2fio2_ratio) < 100 THEN 4
            WHEN MIN(pf.pao2fio2_ratio) < 200 THEN 3
            WHEN MIN(pf.pao2fio2_ratio) < 300 THEN 2
            WHEN MIN(pf.pao2fio2_ratio) < 400 THEN 1
            ELSE 0
        END AS score
    FROM cohort co
    LEFT JOIN pao2fio2_paired pf ON co.stay_id = pf.stay_id AND pf.rn = 1
    GROUP BY co.stay_id
),
-- Coagulation Score (Platelets)
sofa_coagulation AS (
    SELECT co.stay_id,
        CASE WHEN MIN(le.valuenum) < 20 THEN 4 WHEN MIN(le.valuenum) < 50 THEN 3 WHEN MIN(le.valuenum) < 100 THEN 2 WHEN MIN(le.valuenum) < 150 THEN 1 ELSE 0 END AS score
    FROM cohort co
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON co.hadm_id = le.hadm_id
    WHERE le.itemid = 51265 AND le.valuenum IS NOT NULL AND le.charttime BETWEEN co.intime AND co.endtime_72hr
    GROUP BY co.stay_id
),
-- Liver Score (Bilirubin)
sofa_liver AS (
    SELECT co.stay_id,
        CASE WHEN MAX(le.valuenum) >= 12.0 THEN 4 WHEN MAX(le.valuenum) >= 6.0 THEN 3 WHEN MAX(le.valuenum) >= 2.0 THEN 2 WHEN MAX(le.valuenum) >= 1.2 THEN 1 ELSE 0 END AS score
    FROM cohort co
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON co.hadm_id = le.hadm_id
    WHERE le.itemid = 50885 AND le.valuenum IS NOT NULL AND le.charttime BETWEEN co.intime AND co.endtime_72hr
    GROUP BY co.stay_id
),
-- Cardiovascular Score (MAP and Vasopressors)
sofa_cardiovascular AS (
    WITH map_vals AS (
        SELECT co.stay_id, MIN(ce.valuenum) as min_map
        FROM cohort co
        INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON co.stay_id = ce.stay_id
        WHERE ce.itemid IN (220052, 225312, 220181) AND ce.valuenum IS NOT NULL AND ce.charttime BETWEEN co.intime AND co.endtime_72hr
        GROUP BY co.stay_id
    ),
    vaso_usage AS (
        SELECT co.stay_id, 1 as used_vaso
        FROM cohort co
        INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie ON co.stay_id = ie.stay_id
        WHERE ie.itemid IN (221906, 221289, 221662, 221653) AND ie.rate > 0 AND ie.starttime BETWEEN co.intime AND co.endtime_72hr
        GROUP BY co.stay_id
    )
    SELECT co.stay_id, GREATEST(CASE WHEN mv.min_map < 70 THEN 1 ELSE 0 END, CASE WHEN vu.used_vaso = 1 THEN 2 ELSE 0 END) AS score
    FROM cohort co
    LEFT JOIN map_vals mv ON co.stay_id = mv.stay_id
    LEFT JOIN vaso_usage vu ON co.stay_id = vu.stay_id
),
-- CNS Score (Glasgow Coma Scale)
sofa_cns AS (
    SELECT co.stay_id,
        CASE WHEN MIN(ce.valuenum) <= 5 THEN 4 WHEN MIN(ce.valuenum) <= 8 THEN 3 WHEN MIN(ce.valuenum) <= 12 THEN 2 WHEN MIN(ce.valuenum) <= 14 THEN 1 ELSE 0 END AS score
    FROM cohort co
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON co.stay_id = ce.stay_id
    WHERE ce.itemid IN (198, 226758) AND ce.valuenum IS NOT NULL AND ce.charttime BETWEEN co.intime AND co.endtime_72hr
    GROUP BY co.stay_id
),
-- Renal Score (Creatinine)
sofa_renal AS (
    SELECT co.stay_id,
        CASE WHEN MAX(le.valuenum) >= 5.0 THEN 4 WHEN MAX(le.valuenum) >= 3.5 THEN 3 WHEN MAX(le.valuenum) >= 2.0 THEN 2 WHEN MAX(le.valuenum) >= 1.2 THEN 1 ELSE 0 END AS score
    FROM cohort co
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON co.hadm_id = le.hadm_id
    WHERE le.itemid = 50912 AND le.valuenum IS NOT NULL AND le.charttime BETWEEN co.intime AND co.endtime_72hr
    GROUP BY co.stay_id
),
-- Part 3: Combine scores, find threshold, and identify high-risk group
instability_scores AS (
    SELECT co.stay_id, co.hadm_id,
        COALESCE(resp.score, 0) + COALESCE(coag.score, 0) + COALESCE(liv.score, 0) +
        COALESCE(cardio.score, 0) + COALESCE(cns.score, 0) + COALESCE(ren.score, 0)
        AS total_instability_score
    FROM cohort co
    LEFT JOIN sofa_respiration resp ON co.stay_id = resp.stay_id
    LEFT JOIN sofa_coagulation coag ON co.stay_id = coag.stay_id
    LEFT JOIN sofa_liver liv ON co.stay_id = liv.stay_id
    LEFT JOIN sofa_cardiovascular cardio ON co.stay_id = cardio.stay_id
    LEFT JOIN sofa_cns cns ON co.stay_id = cns.stay_id
    LEFT JOIN sofa_renal ren ON co.stay_id = ren.stay_id
),
score_threshold AS (
    SELECT PERCENTILE_CONT(total_instability_score, 0.9) OVER() AS p90_score
    FROM instability_scores LIMIT 1
),
high_risk_cohort AS (
    SELECT hadm_id, stay_id FROM instability_scores
    WHERE total_instability_score >= (SELECT p90_score FROM score_threshold)
),

-- Part 4: Create summary tables for final analysis
critical_labs_all_admissions AS (
    SELECT hadm_id,
        MAX(CASE WHEN itemid = 50813 AND valuenum > 4.0 THEN 1 ELSE 0 END) AS has_high_lactate,
        MAX(CASE WHEN itemid = 51265 AND valuenum < 50 THEN 1 ELSE 0 END) AS has_low_platelets,
        MAX(CASE WHEN itemid = 50912 AND valuenum > 2.0 THEN 1 ELSE 0 END) AS has_high_creatinine,
        MAX(CASE WHEN itemid = 50885 AND valuenum > 2.0 THEN 1 ELSE 0 END) AS has_high_bilirubin
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE hadm_id IS NOT NULL GROUP BY hadm_id
),
high_risk_summary AS (
    SELECT AVG(adm.hospital_expire_flag) as mortality_rate, AVG(icu.los) as mean_icu_los_days
    FROM high_risk_cohort hr
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON hr.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON hr.stay_id = icu.stay_id
),
high_risk_lab_summary AS (
    SELECT
        SAFE_DIVIDE(SUM(cl.has_high_lactate), COUNT(hr.hadm_id)) AS rate_high_lactate,
        SAFE_DIVIDE(SUM(cl.has_low_platelets), COUNT(hr.hadm_id)) AS rate_low_platelets,
        SAFE_DIVIDE(SUM(cl.has_high_creatinine), COUNT(hr.hadm_id)) AS rate_high_creatinine,
        SAFE_DIVIDE(SUM(cl.has_high_bilirubin), COUNT(hr.hadm_id)) AS rate_high_bilirubin
    FROM high_risk_cohort hr
    LEFT JOIN critical_labs_all_admissions cl ON hr.hadm_id = cl.hadm_id
),
general_inpatient_lab_summary AS (
    SELECT
        SAFE_DIVIDE(SUM(has_high_lactate), COUNT(hadm_id)) AS rate_high_lactate,
        SAFE_DIVIDE(SUM(has_low_platelets), COUNT(hadm_id)) AS rate_low_platelets,
        SAFE_DIVIDE(SUM(has_high_creatinine), COUNT(hadm_id)) AS rate_high_creatinine,
        SAFE_DIVIDE(SUM(has_high_bilirubin), COUNT(hadm_id)) AS rate_high_bilirubin
    FROM critical_labs_all_admissions
)
-- Final Select: Combine all metrics into a single row report
SELECT
    st.p90_score AS instability_score_90th_percentile,
    hrs.mortality_rate AS high_risk_ards_mortality_rate,
    hrs.mean_icu_los_days AS high_risk_ards_mean_icu_los_days,
    hrls.rate_high_lactate AS high_risk_ards_rate_high_lactate,
    gils.rate_high_lactate AS general_inpatients_rate_high_lactate,
    hrls.rate_low_platelets AS high_risk_ards_rate_low_platelets,
    gils.rate_low_platelets AS general_inpatients_rate_low_platelets,
    hrls.rate_high_creatinine AS high_risk_ards_rate_high_creatinine,
    gils.rate_high_creatinine AS general_inpatients_rate_high_creatinine,
    hrls.rate_high_bilirubin AS high_risk_ards_rate_high_bilirubin,
    gils.rate_high_bilirubin AS general_inpatients_rate_high_bilirubin
FROM
    score_threshold st,
    high_risk_summary hrs,
    high_risk_lab_summary hrls,
    general_inpatient_lab_summary gils;