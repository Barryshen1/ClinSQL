SELECT hadm_id, is_hhs_female_68_78, has_hyperkalemia_risk_drug, COUNT(...) AS med_complexity
  FROM medications_72h
  GROUP BY ...
),
percentile_ranks AS (
  SELECT *,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS percentile_rank
  FROM medication_complexity
);