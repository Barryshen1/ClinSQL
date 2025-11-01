WITH cohort AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.hospital_expire_flag,
    a.admittime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 59 AND 69
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

-- Identify AKI and ARDS diagnoses
diagnoses AS (
  SELECT
    d.hadm_id,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code LIKE '584%') 
            OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%') 
          THEN 1 ELSE 0 
        END) AS has_aki,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND d.icd_code = '51882') 
            OR (d.icd_version = 10 AND d.icd_code = 'J80') 
          THEN 1 ELSE 0 
        END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.hadm_id
),

-- Calculate Charlson Comorbidity Index
charlson AS (
  SELECT
    d.hadm_id,
    SUM(charlson_weight) AS charlson_score
  FROM (
    SELECT
      d.hadm_id,
      d.icd_code,
      d.icd_version,
      CASE
        -- Myocardial infarction
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') THEN 1
        -- Congestive heart failure
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1
        -- Peripheral vascular disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '440%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I70%') THEN 1
        -- Cerebrovascular disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%' OR d.icd_code LIKE '436%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'G45%' OR d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'I63%' OR d.icd_code LIKE 'I64%' OR d.icd_code LIKE 'I65%' OR d.icd_code LIKE 'I66%' OR d.icd_code LIKE 'I67%' OR d.icd_code LIKE 'I68%' OR d.icd_code LIKE 'I69%') THEN 1
        -- Dementia
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '290%' OR d.icd_code LIKE '2948%' OR d.icd_code LIKE '3312%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'F00%' OR d.icd_code LIKE 'F01%' OR d.icd_code LIKE 'F02%' OR d.icd_code LIKE 'F03%' OR d.icd_code LIKE 'G30%') THEN 1
        -- Chronic pulmonary disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '490%' OR d.icd_code LIKE '491%' OR d.icd_code LIKE '492%' OR d.icd_code LIKE '493%' OR d.icd_code LIKE '494%' OR d.icd_code LIKE '495%' OR d.icd_code LIKE '496%' OR d.icd_code LIKE '500%' OR d.icd_code LIKE '501%' OR d.icd_code LIKE '502%' OR d.icd_code LIKE '503%' OR d.icd_code LIKE '504%' OR d.icd_code LIKE '505%' OR d.icd_code LIKE '5064%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'J40%' OR d.icd_code LIKE 'J41%' OR d.icd_code LIKE 'J42%' OR d.icd_code LIKE 'J43%' OR d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J45%' OR d.icd_code LIKE 'J46%' OR d.icd_code LIKE 'J47%' OR d.icd_code LIKE 'J60%' OR d.icd_code LIKE 'J61%' OR d.icd_code LIKE 'J62%' OR d.icd_code LIKE 'J63%' OR d.icd_code LIKE 'J64%' OR d.icd_code LIKE 'J65%' OR d.icd_code LIKE 'J66%' OR d.icd_code LIKE 'J67%' OR d.icd_code LIKE 'J68%' OR d.icd_code LIKE 'J69%' OR d.icd_code LIKE 'J701%' OR d.icd_code LIKE 'J703%') THEN 1
        -- Rheumatic disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '714%' OR d.icd_code LIKE '725%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'M05%' OR d.icd_code LIKE 'M06%' OR d.icd_code LIKE 'M32%' OR d.icd_code LIKE 'M33%' OR d.icd_code LIKE 'M34%' OR d.icd_code LIKE 'M35.1') THEN 1
        -- Peptic ulcer disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '531%' OR d.icd_code LIKE '532%' OR d.icd_code LIKE '533%' OR d.icd_code LIKE '534%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'K25%' OR d.icd_code LIKE 'K26%' OR d.icd_code LIKE 'K27%' OR d.icd_code LIKE 'K28%') THEN 1
        -- Mild liver disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '570%' OR d.icd_code LIKE '571%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'I86%' OR d.icd_code LIKE 'K70%' OR d.icd_code LIKE 'K71%' OR d.icd_code LIKE 'K72%' OR d.icd_code LIKE 'K73%' OR d.icd_code LIKE 'K74%' OR d.icd_code LIKE 'K76%') THEN 1
        -- Diabetes without complication
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%' AND d.icd_code NOT LIKE '2501%' AND d.icd_code NOT LIKE '2502%' AND d.icd_code NOT LIKE '2503%' AND d.icd_code NOT LIKE '2504%' AND d.icd_code NOT LIKE '2505%' AND d.icd_code NOT LIKE '2506%' AND d.icd_code NOT LIKE '2507%' AND d.icd_code NOT LIKE '2508%' AND d.icd_code NOT LIKE '2509%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'E08%' AND d.icd_code NOT LIKE 'E081%' AND d.icd_code NOT LIKE 'E082%' AND d.icd_code NOT LIKE 'E083%' AND d.icd_code NOT LIKE 'E084%' AND d.icd_code NOT LIKE 'E085%' AND d.icd_code NOT LIKE 'E086%' 
                 OR d.icd_code LIKE 'E09%' AND d.icd_code NOT LIKE 'E091%' AND d.icd_code NOT LIKE 'E092%' AND d.icd_code NOT LIKE 'E093%' AND d.icd_code NOT LIKE 'E094%' AND d.icd_code NOT LIKE 'E095%' AND d.icd_code NOT LIKE 'E096%'
                 OR d.icd_code LIKE 'E10%' AND d.icd_code NOT LIKE 'E101%' AND d.icd_code NOT LIKE 'E102%' AND d.icd_code NOT LIKE 'E103%' AND d.icd_code NOT LIKE 'E104%' AND d.icd_code NOT LIKE 'E105%' AND d.icd_code NOT LIKE 'E106%'
                 OR d.icd_code LIKE 'E11%' AND d.icd_code NOT LIKE 'E111%' AND d.icd_code NOT LIKE 'E112%' AND d.icd_code NOT LIKE 'E113%' AND d.icd_code NOT LIKE 'E114%' AND d.icd_code NOT LIKE 'E115%' AND d.icd_code NOT LIKE 'E116%'
                 OR d.icd_code LIKE 'E13%' AND d.icd_code NOT LIKE 'E131%' AND d.icd_code NOT LIKE 'E132%' AND d.icd_code NOT LIKE 'E133%' AND d.icd_code NOT LIKE 'E134%' AND d.icd_code NOT LIKE 'E135%' AND d.icd_code NOT LIKE 'E136%') THEN 1
        -- Diabetes with complication
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '2501%' OR d.icd_code LIKE '2502%' OR d.icd_code LIKE '2503%' OR d.icd_code LIKE '2504%' OR d.icd_code LIKE '2505%' OR d.icd_code LIKE '2506%' OR d.icd_code LIKE '2507%' OR d.icd_code LIKE '2508%' OR d.icd_code LIKE '2509%')) 
             OR (d.icd_version = 10 AND (d.icd_code LIKE 'E081%' OR d.icd_code LIKE 'E082%' OR d.icd_code LIKE 'E083%' OR d.icd_code LIKE 'E084%' OR d.icd_code LIKE 'E085%' OR d.icd_code LIKE 'E086%'
                 OR d.icd_code LIKE 'E091%' OR d.icd_code LIKE 'E092%' OR d.icd_code LIKE 'E093%' OR d.icd_code LIKE 'E094%' OR d.icd_code LIKE 'E095%' OR d.icd_code LIKE 'E096%'
                 OR d.icd_code LIKE 'E101%' OR d.icd_code LIKE 'E102%' OR d.icd_code LIKE 'E103%' OR d.icd_code LIKE 'E104%' OR d.icd_code LIKE 'E105%' OR d.icd_code LIKE 'E106%'
                 OR d.icd_code LIKE 'E111%' OR d.icd_code LIKE 'E112%' OR d.icd_code LIKE 'E113%' OR d.icd_code LIKE 'E114%' OR d.icd_code LIKE 'E115%' OR d.icd_code LIKE 'E116%'
                 OR d.icd_code LIKE 'E131%' OR d.icd_code LIKE 'E132%' OR d.icd_code LIKE 'E133%' OR d.icd_code LIKE 'E134%' OR d.icd_code LIKE 'E135%' OR d.icd_code LIKE 'E136%')) THEN 2
        -- Paraplegia
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '342%' OR d.icd_code LIKE '343%' OR d.icd_code LIKE '3440%' OR d.icd_code LIKE '3441%' OR d.icd_code LIKE '3442%' OR d.icd_code LIKE '3443%' OR d.icd_code LIKE '3444%' OR d.icd_code LIKE '3445%' OR d.icd_code LIKE '3446%' OR d.icd_code LIKE '3449%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'G82%' OR d.icd_code LIKE 'Q668%' OR d.icd_code LIKE 'Q751%') THEN 2
        -- Renal disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '582%' OR d.icd_code LIKE '583%' OR d.icd_code LIKE '585%' OR d.icd_code LIKE '586%' OR d.icd_code LIKE '5880%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%' OR d.icd_code LIKE 'Q270%' OR d.icd_code LIKE 'Z49%' OR d.icd_code LIKE 'Z940%' OR d.icd_code LIKE 'Z992%') THEN 2
        -- Malignant cancer
        WHEN (d.icd_version = 9 AND (d.icd_code LIKE '140%' OR d.icd_code LIKE '141%' OR d.icd_code LIKE '142%' OR d.icd_code LIKE '143%' OR d.icd_code LIKE '144%' OR d.icd_code LIKE '145%' OR d.icd_code LIKE '146%' OR d.icd_code LIKE '147%' OR d.icd_code LIKE '148%' OR d.icd_code LIKE '149%' OR d.icd_code LIKE '150%' OR d.icd_code LIKE '151%' OR d.icd_code LIKE '152%' OR d.icd_code LIKE '153%' OR d.icd_code LIKE '154%' OR d.icd_code LIKE '155%' OR d.icd_code LIKE '156%' OR d.icd_code LIKE '157%' OR d.icd_code LIKE '158%' OR d.icd_code LIKE '159%' OR d.icd_code LIKE '160%' OR d.icd_code LIKE '161%' OR d.icd_code LIKE '162%' OR d.icd_code LIKE '163%' OR d.icd_code LIKE '164%' OR d.icd_code LIKE '165%' OR d.icd_code LIKE '170%' OR d.icd_code LIKE '171%' OR d.icd_code LIKE '172%' OR d.icd_code LIKE '174%' OR d.icd_code LIKE '175%' OR d.icd_code LIKE '176%' OR d.icd_code LIKE '179%' OR d.icd_code LIKE '180%' OR d.icd_code LIKE '181%' OR d.icd_code LIKE '182%' OR d.icd_code LIKE '183%' OR d.icd_code LIKE '184%' OR d.icd_code LIKE '185%' OR d.icd_code LIKE '186%' OR d.icd_code LIKE '187%' OR d.icd_code LIKE '188%' OR d.icd_code LIKE '189%' OR d.icd_code LIKE '190%' OR d.icd_code LIKE '191%' OR d.icd_code LIKE '192%' OR d.icd_code LIKE '193%' OR d.icd_code LIKE '194%' OR d.icd_code LIKE '195%' OR d.icd_code LIKE '200%' OR d.icd_code LIKE '201%' OR d.icd_code LIKE '202%' OR d.icd_code LIKE '203%' OR d.icd_code LIKE '204%' OR d.icd_code LIKE '205%' OR d.icd_code LIKE '206%' OR d.icd_code LIKE '207%' OR d.icd_code LIKE '208%')) 
             OR (d.icd_version = 10 AND (d.icd_code LIKE 'C00%' OR d.icd_code LIKE 'C01%' OR d.icd_code LIKE 'C02%' OR d.icd_code LIKE 'C03%' OR d.icd_code LIKE 'C04%' OR d.icd_code LIKE 'C05%' OR d.icd_code LIKE 'C06%' OR d.icd_code LIKE 'C07%' OR d.icd_code LIKE 'C08%' OR d.icd_code LIKE 'C09%' OR d.icd_code LIKE 'C10%' OR d.icd_code LIKE 'C11%' OR d.icd_code LIKE 'C12%' OR d.icd_code LIKE 'C13%' OR d.icd_code LIKE 'C14%' OR d.icd_code LIKE 'C15%' OR d.icd_code LIKE 'C16%' OR d.icd_code LIKE 'C17%' OR d.icd_code LIKE 'C18%' OR d.icd_code LIKE 'C19%' OR d.icd_code LIKE 'C20%' OR d.icd_code LIKE 'C21%' OR d.icd_code LIKE 'C22%' OR d.icd_code LIKE 'C23%' OR d.icd_code LIKE 'C24%' OR d.icd_code LIKE 'C25%' OR d.icd_code LIKE 'C26%' OR d.icd_code LIKE 'C30%' OR d.icd_code LIKE 'C31%' OR d.icd_code LIKE 'C32%' OR d.icd_code LIKE 'C33%' OR d.icd_code LIKE 'C34%' OR d.icd_code LIKE 'C37%' OR d.icd_code LIKE 'C38%' OR d.icd_code LIKE 'C39%' OR d.icd_code LIKE 'C40%' OR d.icd_code LIKE 'C41%' OR d.icd_code LIKE 'C43%' OR d.icd_code LIKE 'C45%' OR d.icd_code LIKE 'C46%' OR d.icd_code LIKE 'C47%' OR d.icd_code LIKE 'C48%' OR d.icd_code LIKE 'C49%' OR d.icd_code LIKE 'C50%' OR d.icd_code LIKE 'C51%' OR d.icd_code LIKE 'C52%' OR d.icd_code LIKE 'C53%' OR d.icd_code LIKE 'C54%' OR d.icd_code LIKE 'C55%' OR d.icd_code LIKE 'C56%' OR d.icd_code LIKE 'C57%' OR d.icd_code LIKE 'C58%' OR d.icd_code LIKE 'C60%' OR d.icd_code LIKE 'C61%' OR d.icd_code LIKE 'C62%' OR d.icd_code LIKE 'C63%' OR d.icd_code LIKE 'C64%' OR d.icd_code LIKE 'C65%' OR d.icd_code LIKE 'C66%' OR d.icd_code LIKE 'C67%' OR d.icd_code LIKE 'C68%' OR d.icd_code LIKE 'C69%' OR d.icd_code LIKE 'C70%' OR d.icd_code LIKE 'C71%' OR d.icd_code LIKE 'C72%' OR d.icd_code LIKE 'C73%' OR d.icd_code LIKE 'C74%' OR d.icd_code LIKE 'C75%' OR d.icd_code LIKE 'C76%' OR d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C80%' OR d.icd_code LIKE 'C81%' OR d.icd_code LIKE 'C82%' OR d.icd_code LIKE 'C83%' OR d.icd_code LIKE 'C84%' OR d.icd_code LIKE 'C85%' OR d.icd_code LIKE 'C86%' OR d.icd_code LIKE 'C88%' OR d.icd_code LIKE 'C90%' OR d.icd_code LIKE 'C91%' OR d.icd_code LIKE 'C92%' OR d.icd_code LIKE 'C93%' OR d.icd_code LIKE 'C94%' OR d.icd_code LIKE 'C95%' OR d.icd_code LIKE 'C96%')) THEN 2
        -- Moderate or severe liver disease
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '4560%' OR d.icd_code LIKE '4561%' OR d.icd_code LIKE '4562%' OR d.icd_code LIKE '5722%' OR d.icd_code LIKE '5723%' OR d.icd_code LIKE '5724%' OR d.icd_code LIKE '5728%' OR d.icd_code LIKE '5729%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'I85%' OR d.icd_code LIKE 'I982%' OR d.icd_code LIKE 'K704%' OR d.icd_code LIKE 'K711%' OR d.icd_code LIKE 'K72%' OR d.icd_code LIKE 'K76%' OR d.icd_code LIKE 'K77%') THEN 3
        -- Metastatic solid tumor
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '196%' OR d.icd_code LIKE '197%' OR d.icd_code LIKE '198%' OR d.icd_code LIKE '199%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'C77%' OR d.icd_code LIKE 'C78%' OR d.icd_code LIKE 'C79%' OR d.icd_code LIKE 'C80%') THEN 6
        -- AIDS
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '042%' OR d.icd_code LIKE '043%' OR d.icd_code LIKE '044%') 
             OR (d.icd_version = 10 AND d.icd_code LIKE 'B20%' OR d.icd_code LIKE 'B21%' OR d.icd_code LIKE 'B22%' OR d.icd_code LIKE 'B24%') THEN 6
        ELSE 0
      END AS charlson_weight
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id IN (SELECT hadm_id FROM cohort)
  ) d
  GROUP BY d.hadm_id
)

SELECT
  -- In-hospital mortality rate
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  
  -- AKI rate
  AVG(CAST(d.has_aki AS FLOAT64)) AS aki_rate,
  
  -- ARDS rate
  AVG(CAST(d.has_ards AS FLOAT64)) AS ards_rate,
  
  -- Median survival among in-hospital deaths (in days)
  APPROX_QUANTILES(
    DATETIME_DIFF(c.deathtime, c.admittime, DAY), 
    100
  )[OFFSET(50)] AS median_survival_days,
  
  -- Composite risk score distribution
  MIN(ch.charlson_score) AS charlson_min,
  APPROX_QUANTILES(ch.charlson_score, 100)[OFFSET(25)] AS charlson_p25,
  APPROX_QUANTILES(ch.charlson_score, 100)[OFFSET(50)] AS charlson_median,
  APPROX_QUANTILES(ch.charlson_score, 100)[OFFSET(75)] AS charlson_p75,
  APPROX_QUANTILES(ch.charlson_score, 100)[OFFSET(90)] AS charlson_p90,
  MAX(ch.charlson_score) AS charlson_max

FROM cohort c
LEFT JOIN diagnoses d ON c.hadm_id = d.hadm_id
LEFT JOIN charlson ch ON c.hadm_id = ch.hadm_id;